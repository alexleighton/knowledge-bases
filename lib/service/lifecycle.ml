module Root = Repository.Root
module Jsonl = Repository.Jsonl
module Io = Control.Io
module Namespace = Data.Namespace

type error =
  | Repository_error of string
  | Validation_error of string

type file_action = Deleted | Not_found

type agents_md_action = Created | Appended | Already_present
type git_exclude_action = Excluded | Already_excluded
type agents_md_uninstall_action =
  | File_deleted | Section_removed | Section_modified | Not_found
type git_exclude_uninstall_action = Entry_removed | Entry_not_found

type init_result = {
  directory   : string;
  namespace   : string;
  db_file     : string;
  mode        : string;
  agents_md   : agents_md_action;
  git_exclude : git_exclude_action;
}

type uninstall_result = {
  directory   : string;
  database    : file_action;
  jsonl       : file_action;
  agents_md   : agents_md_uninstall_action;
  git_exclude : git_exclude_uninstall_action;
}

let agents_md_filename = "AGENTS.md"
let agents_md_section_heading = "## ※ Knowledge Base"
let agents_md_marker = "※"

let agents_md_template = {|## ※ Knowledge Base

This repository uses `bs` to track todos and notes. Use it to
externalize work you've identified, decisions, and research.

```
# Create items (content from --content or stdin)
echo "Description" | bs add todo "Title"
echo "Research findings" | bs add note "Title"

# Browse
bs list
bs list --available
bs show kb-0

# Claim and work on todos
bs next --show
bs claim kb-0

# Complete and archive
bs resolve kb-0 kb-1
bs archive kb-5 kb-6

# Link items after creation
bs relate kb-2 --depends-on kb-3 --related-to kb-4
```

Run `bs --help` for the full command reference.
※
|}

(* --- Initialization helpers --- *)

let resolve_directory = function
  | None -> (
      match Git.find_repo_root () with
      | Some dir -> Ok dir
      | None ->
          Error
            (Validation_error
               "Not inside a git repository. Use -d to specify a directory."))
  | Some dir ->
      let resolved =
        if Filename.is_relative dir then Filename.concat (Sys.getcwd ()) dir else dir
      in
      if not (Sys.file_exists resolved) then
        Error (Validation_error ("Directory does not exist: " ^ resolved))
      else if not (Sys.is_directory resolved) then
        Error (Validation_error ("Path is not a directory: " ^ resolved))
      else if not (Git.is_git_root resolved) then
        Error
          (Validation_error
             ("Directory is not a git repository root: " ^ resolved))
      else
        Ok resolved

let resolve_namespace ~directory = function
  | Some ns ->
      Namespace.validate ns
      |> Result.map Namespace.to_string
      |> Result.map_error (fun msg -> Validation_error msg)
  | None ->
      let derived = Namespace.of_name (Git.repo_name directory) in
      Namespace.validate derived
      |> Result.map Namespace.to_string
      |> Result.map_error (fun reason ->
             Validation_error
               (Printf.sprintf
                  "Derived namespace \"%s\" is invalid (%s). Use -n to specify one."
                  derived reason))

let map_root_error (Repository.Root.Backend_failure msg) =
  Repository_error msg

let map_jsonl_error = function
  | Repository.Jsonl.Io_error msg -> Repository_error msg
  | Repository.Jsonl.Parse_error msg -> Repository_error msg

let _map_config_svc_error = function
  | Config_service.Unknown_key k -> Validation_error ("unknown config key: " ^ k)
  | Config_service.Validation_error msg -> Validation_error msg
  | Config_service.Nothing_to_update -> Validation_error "nothing to update"
  | Config_service.Backend_error msg -> Repository_error msg

let _set_config_init cfg key value =
  match Config_service.set ~run_on_set:false cfg key value with
  | Ok () | Error Config_service.Nothing_to_update -> Ok ()
  | Error (Config_service.Unknown_key _ | Config_service.Validation_error _
          | Config_service.Backend_error _ as e) ->
      Error (_map_config_svc_error e)

let install_database ~db_file ~dir ~namespace ~gc_max_age ~mode =
  let open Result.Syntax in
  let* root =
    Root.init ~db_file ~namespace:(Some namespace)
    |> Result.map_error (fun (Root.Backend_failure msg) ->
           Repository_error msg)
  in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () ->
      let cfg = Config_service.init root ~dir in
      let* () = _set_config_init cfg "namespace" namespace in
      let* () = match gc_max_age with
        | Some age -> _set_config_init cfg "gc_max_age" age
        | None -> Ok ()
      in
      let* () = _set_config_init cfg "mode" mode in
      Ok ())

let _has_kb_heading contents =
  Data.String.contains_substring ~needle:agents_md_section_heading contents

let install_agents_md ~directory =
  let path = Filename.concat directory agents_md_filename in
  if Sys.file_exists path then begin
    let existing = Io.read_file path in
    if _has_kb_heading existing then
      Already_present
    else begin
      let new_contents = existing ^ "\n" ^ agents_md_template in
      Io.write_file ~path ~contents:new_contents;
      Appended
    end
  end else begin
    Io.write_file ~path ~contents:agents_md_template;
    Created
  end

let install_git_exclude ~directory =
  match Git.add_exclude ~directory Data.Kb_filenames.db with
  | Git.Added -> Excluded
  | Git.Already_present -> Already_excluded

(* --- Uninstall helpers --- *)

let uninstall_file path : file_action =
  if Sys.file_exists path then begin Sys.remove path; Deleted end
  else Not_found

let _find_marker_section contents =
  let lines = String.split_on_char '\n' contents in
  let heading_prefix = agents_md_section_heading in
  let rec find_heading i = function
    | [] -> None
    | line :: rest ->
        if String.starts_with ~prefix:heading_prefix (String.trim line) then
          find_footer i (i + 1) rest
        else
          find_heading (i + 1) rest
  and find_footer start i = function
    | [] -> None
    | line :: rest ->
        if String.trim line = agents_md_marker then
          Some (start, i)
        else
          find_footer start (i + 1) rest
  in
  find_heading 0 lines

let _remove_lines contents ~start ~stop =
  let lines = String.split_on_char '\n' contents in
  let kept = List.filteri (fun i _ -> i < start || i > stop) lines in
  let result = String.concat "\n" kept in
  String.trim result

let uninstall_agents_md ~directory : agents_md_uninstall_action =
  let path = Filename.concat directory agents_md_filename in
  if not (Sys.file_exists path) then Not_found
  else
    let contents = Io.read_file path in
    match _find_marker_section contents with
    | Some (start, stop) ->
        let remaining = _remove_lines contents ~start ~stop in
        if remaining = "" then begin
          Sys.remove path; File_deleted
        end else begin
          Io.write_file ~path ~contents:(remaining ^ "\n");
          Section_removed
        end
    | None ->
        if _has_kb_heading contents then Section_modified
        else Not_found

let uninstall_git_exclude ~directory =
  match Git.remove_exclude ~directory Data.Kb_filenames.db with
  | Git.Removed -> Entry_removed
  | Git.Remove_not_found -> Entry_not_found

(* --- Public operations --- *)

let open_kb () =
  match Git.find_repo_root () with
  | None ->
      Error
        (Validation_error
           "Not inside a git repository. Run 'bs add' from within a git repository.")
  | Some dir ->
      let db_file = Filename.concat dir Data.Kb_filenames.db in
      if Sys.file_exists db_file then
        Root.init ~db_file ~namespace:None
        |> Result.map (fun root -> (root, dir))
        |> Result.map_error map_root_error
      else
        let jsonl_path = Filename.concat dir Data.Kb_filenames.jsonl in
        if Sys.file_exists jsonl_path then
          let open Result.Syntax in
          let* header =
            Jsonl.read_header ~path:jsonl_path
            |> Result.map_error map_jsonl_error
          in
          let* root =
            Root.init ~db_file ~namespace:(Some header.Jsonl.namespace)
            |> Result.map_error map_root_error
          in
          let cfg = Config_service.init root ~dir in
          let* () = _set_config_init cfg "namespace" header.Jsonl.namespace in
          Ok (root, dir)
        else
          Error
            (Validation_error "No knowledge base found. Run 'bs init' first.")

let init_kb ~directory ~namespace ~gc_max_age ~mode =
  let open Result.Syntax in
  let* directory = resolve_directory directory in
  let* namespace = resolve_namespace ~directory namespace in
  let db_file = Filename.concat directory Data.Kb_filenames.db in
  let mode = match mode with Some m -> m | None -> "shared" in
  if Sys.file_exists db_file then
    Error
      (Validation_error
         (Printf.sprintf "Knowledge base already initialised at %s." db_file))
  else
    let* () = install_database ~db_file ~dir:directory ~namespace ~gc_max_age ~mode in
    let agents_md = install_agents_md ~directory in
    let git_exclude = install_git_exclude ~directory in
    Ok { directory; namespace; db_file; mode; agents_md; git_exclude }

let uninstall_kb ~directory =
  let open Result.Syntax in
  let* directory = resolve_directory directory in
  let database = uninstall_file (Filename.concat directory Data.Kb_filenames.db) in
  let jsonl = uninstall_file (Filename.concat directory Data.Kb_filenames.jsonl) in
  let agents_md = uninstall_agents_md ~directory in
  let git_exclude = uninstall_git_exclude ~directory in
  Ok { directory; database; jsonl; agents_md; git_exclude }
