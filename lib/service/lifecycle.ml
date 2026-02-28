module Root = Repository.Root
module Config = Repository.Config
module Git = Control.Git
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
echo "Description" | bs add todo "Title"
bs list todo --status open
bs show kb-0
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

let open_kb () =
  match Git.find_repo_root () with
  | None ->
      Error
        (Validation_error
           "Not inside a git repository. Run 'bs add' from within a git repository.")
  | Some dir ->
      let db_file = Filename.concat dir db_filename in
      if not (Sys.file_exists db_file) then
        Error
          (Validation_error "No knowledge base found. Run 'bs init' first.")
      else
        Root.init ~db_file ~namespace:None
        |> Result.map (fun root -> (root, dir))
        |> Result.map_error (fun (Root.Backend_failure msg) ->
               Repository_error msg)

let init_kb ~directory ~namespace =
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
        Config.set (Root.config root) "namespace" namespace
        |> Result.map_error (fun err ->
               match err with
               | Config.Backend_failure msg -> Repository_error msg
               | Config.Not_found key ->
                   Repository_error ("Config key not found: " ^ key))
        |> Result.map (fun () ->
               let agents_md = install_agents_md ~directory in
               let git_exclude = install_git_exclude ~directory in
               { directory; namespace; db_file; agents_md; git_exclude }))
