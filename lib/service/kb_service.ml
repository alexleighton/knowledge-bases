module Note = Repository.Note
module Root = Repository.Root
module Config = Repository.Config
module Git = Control.Git
module Namespace = Data.Namespace

type t = {
  note_repo : Note.t;
}

type init_result = {
  directory : string;
  namespace : string;
  db_file   : string;
}

type error =
  | Repository_error of string
  | Validation_error of string

let init root =
  { note_repo = Repository.Root.note root }

let repository_error_label = function
  | Note.Backend_failure msg -> Repository_error msg
  | Note.Duplicate_niceid niceid ->
      Repository_error ("duplicate nice id " ^ Data.Identifier.to_string niceid)
  | Note.Not_found _ -> Repository_error "note not found"

let add_note t ~title ~content =
  Note.create t.note_repo ~title ~content
  |> Result.map_error repository_error_label

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

let init_kb ~directory ~namespace =
  let open Result.Syntax in
  let* directory = resolve_directory directory in
  let* namespace = resolve_namespace ~directory namespace in
  let db_file = Filename.concat directory ".kbases.db" in
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
        |> Result.map (fun () -> { directory; namespace; db_file }))
