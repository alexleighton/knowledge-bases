module Note = Repository.Note
module Todo = Repository.Todo
module Root = Repository.Root
module Config = Repository.Config
module Git = Control.Git
module Result_data = Data.Result
module Namespace = Data.Namespace

let _db_filename = ".kbases.db"

type t = {
  note_repo : Note.t;
  todo_repo : Todo.t;
}

type init_result = {
  directory : string;
  namespace : string;
  db_file   : string;
}

type error =
  | Repository_error of string
  | Validation_error of string

type item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

let init root =
  { note_repo = Repository.Root.note root; todo_repo = Repository.Root.todo root }

let repository_error_label = function
  | Note.Backend_failure msg -> Repository_error msg
  | Note.Duplicate_niceid niceid ->
      Repository_error ("duplicate nice id " ^ Data.Identifier.to_string niceid)
  | Note.Not_found _ -> Repository_error "note not found"

let todo_repository_error_label = function
  | Todo.Backend_failure msg -> Repository_error msg
  | Todo.Duplicate_niceid niceid ->
      Repository_error ("duplicate nice id " ^ Data.Identifier.to_string niceid)
  | Todo.Not_found _ -> Repository_error "todo not found"

let add_note t ~title ~content =
  Note.create t.note_repo ~title ~content ()
  |> Result.map_error repository_error_label

let add_todo t ~title ~content ?status () =
  Todo.create t.todo_repo ~title ~content ?status ()
  |> Result.map_error todo_repository_error_label

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

let db_filename = _db_filename

let open_kb () =
  match Git.find_repo_root () with
  | None ->
      Error
        (Validation_error
           "Not inside a git repository. Run 'bs add' from within a git repository.")
  | Some dir ->
      let db_file = Filename.concat dir _db_filename in
      if not (Sys.file_exists db_file) then
        Error
          (Validation_error "No knowledge base found. Run 'bs init' first.")
      else
        Root.init ~db_file ~namespace:None
        |> Result.map_error (fun (Root.Backend_failure msg) ->
               Repository_error msg)
        |> Result.map (fun root -> (root, init root))

let init_kb ~directory ~namespace =
  let open Result.Syntax in
  let* directory = resolve_directory directory in
  let* namespace = resolve_namespace ~directory namespace in
  let db_file = Filename.concat directory _db_filename in
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

let _raw_id_of_item = function
  | Todo_item todo -> Data.Identifier.raw_id (Data.Todo.niceid todo)
  | Note_item note -> Data.Identifier.raw_id (Data.Note.niceid note)

let _sort_items items =
  List.sort (fun a b -> Int.compare (_raw_id_of_item a) (_raw_id_of_item b)) items

let list t ~entity_type ~statuses =
  let open Result.Syntax in
  let try_parse_todo status =
    try Some (Data.Todo.status_from_string status) with Invalid_argument _ -> None
  in
  let try_parse_note status =
    try Some (Data.Note.status_from_string status) with Invalid_argument _ -> None
  in
  let parse_todo status =
    match try_parse_todo status with
    | Some s -> Ok s
    | None ->
        Error (Validation_error (Printf.sprintf "invalid status \"%s\" for todo" status))
  in
  let parse_note status =
    match try_parse_note status with
    | Some s -> Ok s
    | None ->
        Error (Validation_error (Printf.sprintf "invalid status \"%s\" for note" status))
  in
  let fetch_todos statuses =
    Todo.list t.todo_repo ~statuses |> Result.map_error todo_repository_error_label
  in
  let fetch_notes statuses =
    Note.list t.note_repo ~statuses |> Result.map_error repository_error_label
  in
  match entity_type with
  | Some "todo" ->
      let* todo_statuses = Result_data.sequence (List.map parse_todo statuses) in
      let+ todos = fetch_todos todo_statuses in
      todos |> List.map (fun todo -> Todo_item todo) |> _sort_items
  | Some "note" ->
      let* note_statuses = Result_data.sequence (List.map parse_note statuses) in
      let+ notes = fetch_notes note_statuses in
      notes |> List.map (fun note -> Note_item note) |> _sort_items
  | Some other ->
      Error (Validation_error (Printf.sprintf "invalid entity type \"%s\"" other))
  | None ->
      let rec partition todo_statuses note_statuses = function
        | [] -> Ok (List.rev todo_statuses, List.rev note_statuses)
        | status :: rest -> (
            match try_parse_todo status with
            | Some todo_status -> partition (todo_status :: todo_statuses) note_statuses rest
            | None -> (
                match try_parse_note status with
                | Some note_status -> partition todo_statuses (note_status :: note_statuses) rest
                | None ->
                    Error (Validation_error (Printf.sprintf "invalid status \"%s\"" status))))
      in
      let* todo_statuses, note_statuses = partition [] [] statuses in
      let should_query_todos = statuses = [] || todo_statuses <> [] in
      let should_query_notes = statuses = [] || note_statuses <> [] in
      let* todos =
        if should_query_todos then fetch_todos todo_statuses else Ok []
      in
      let* notes =
        if should_query_notes then fetch_notes note_statuses else Ok []
      in
      let items =
        (List.map (fun todo -> Todo_item todo) todos)
        @ (List.map (fun note -> Note_item note) notes)
      in
      Ok (_sort_items items)
