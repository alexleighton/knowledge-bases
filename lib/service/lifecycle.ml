module Root = Repository.Root
module Config = Repository.Config
module Jsonl = Repository.Jsonl
module Io = Control.Io
module Namespace = Data.Namespace

let db_filename = ".kbases.db"
let jsonl_filename = ".kbases.jsonl"
let agents_md_filename = "AGENTS.md"
let agents_md_section_heading = "## Knowledge Base"

let agents_md_template = {|## Knowledge Base

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
bs resolve kb-0
bs archive kb-5
```

Run `bs --help` for the full command reference.
|}

type error =
  | Repository_error of string
  | Validation_error of string

type agents_md_action = Created | Appended | Already_present
type git_exclude_action = Excluded | Already_excluded

type init_result = {
  directory   : string;
  namespace   : string;
  db_file     : string;
  agents_md   : agents_md_action;
  git_exclude : git_exclude_action;
}

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

let install_agents_md ~directory =
  let path = Filename.concat directory agents_md_filename in
  if Sys.file_exists path then begin
    let existing = Io.read_file path in
    if Data.String.contains_substring ~needle:agents_md_section_heading existing then
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
  match Git.add_exclude ~directory db_filename with
  | Git.Added -> Excluded
  | Git.Already_present -> Already_excluded

(* --- Public operations --- *)

let open_kb () =
  match Git.find_repo_root () with
  | None ->
      Error
        (Validation_error
           "Not inside a git repository. Run 'bs add' from within a git repository.")
  | Some dir ->
      let db_file = Filename.concat dir db_filename in
      if Sys.file_exists db_file then
        Root.init ~db_file ~namespace:None
        |> Result.map (fun root -> (root, dir))
        |> Result.map_error (fun (Root.Backend_failure msg) ->
               Repository_error msg)
      else
        let jsonl_path = Filename.concat dir jsonl_filename in
        if Sys.file_exists jsonl_path then
          let open Result.Syntax in
          let* header =
            Jsonl.read_header ~path:jsonl_path
            |> Result.map_error (fun err ->
                   match err with
                   | Jsonl.Io_error msg -> Repository_error msg
                   | Jsonl.Parse_error msg -> Repository_error msg)
          in
          let* root =
            Root.init ~db_file ~namespace:(Some header.Jsonl.namespace)
            |> Result.map_error (fun (Root.Backend_failure msg) ->
                   Repository_error msg)
          in
          let* () =
            Config.set (Root.config root) "namespace" header.Jsonl.namespace
            |> Result.map_error (fun err ->
                   match err with
                   | Config.Backend_failure msg -> Repository_error msg
                   | Config.Not_found key ->
                       Repository_error ("Config key not found: " ^ key))
          in
          Ok (root, dir)
        else
          Error
            (Validation_error "No knowledge base found. Run 'bs init' first.")

let _map_config_error e =
  match Item_service.map_config_error e with
  | Item_service.Repository_error msg -> Repository_error msg
  | Item_service.Validation_error msg -> Validation_error msg

let init_kb ~directory ~namespace ~gc_max_age =
  let open Result.Syntax in
  let* directory = resolve_directory directory in
  let* namespace = resolve_namespace ~directory namespace in
  let db_file = Filename.concat directory db_filename in
  if Sys.file_exists db_file then
    Error
      (Validation_error
         (Printf.sprintf "Knowledge base already initialised at %s." db_file))
  else
    let* root =
      Root.init ~db_file ~namespace:(Some namespace)
      |> Result.map_error (fun (Root.Backend_failure msg) ->
             Repository_error msg)
    in
    Fun.protect
      ~finally:(fun () -> Root.close root)
      (fun () ->
        let config = Root.config root in
        let* () = Config.set config "namespace" namespace
                   |> Result.map_error _map_config_error in
        let* () = match gc_max_age with
          | Some age -> Config.set config "gc_max_age" age
                        |> Result.map_error _map_config_error
          | None -> Ok ()
        in
        let agents_md = install_agents_md ~directory in
        let git_exclude = install_git_exclude ~directory in
        Ok { directory; namespace; db_file; agents_md; git_exclude })
