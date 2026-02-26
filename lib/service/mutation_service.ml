module TodoRepo = Repository.Todo
module NoteRepo = Repository.Note

type t = {
  items     : Item_service.t;
  todo_repo : TodoRepo.t;
  note_repo : NoteRepo.t;
}

let init root = {
  items     = Item_service.init root;
  todo_repo = Repository.Root.todo root;
  note_repo = Repository.Root.note root;
}

let parse_status ~entity_name ~from_string s =
  try Ok (from_string s)
  with Invalid_argument _ ->
    Error (Item_service.Validation_error (Printf.sprintf "invalid status %S for %s" s entity_name))

let apply_field_updates
    (type a s) (module E : Data.Entity.S with type t = a and type status = s)
    ~entity_name entity ?status ?title ?content () =
  let open Result.Syntax in
  let* entity =
    match status with
    | None -> Ok entity
    | Some s ->
        let+ s = parse_status ~entity_name ~from_string:E.status_from_string s in
        E.with_status entity s
  in
  let entity = match title with None -> entity | Some t -> E.with_title entity t in
  let entity = match content with None -> entity | Some c -> E.with_content entity c in
  Ok entity

let update t ~identifier ?status ?title ?content () =
  let open Item_service in
  match status, title, content with
  | None, None, None -> Error (Validation_error "nothing to update")
  | _ ->
      let open Result.Syntax in
      let* item = find t.items ~identifier in
      match item with
      | Todo_item todo ->
          let* todo =
            apply_field_updates (module Data.Todo) ~entity_name:"todo"
              todo ?status ?title ?content ()
          in
          let+ todo =
            TodoRepo.update t.todo_repo todo
            |> Result.map_error (map_repo_error ~entity_name:"todo")
          in
          Todo_item todo
      | Note_item note ->
          let* note =
            apply_field_updates (module Data.Note) ~entity_name:"note"
              note ?status ?title ?content ()
          in
          let+ note =
            NoteRepo.update t.note_repo note
            |> Result.map_error (map_repo_error ~entity_name:"note")
          in
          Note_item note

let resolve t ~identifier =
  let open Item_service in
  let open Result.Syntax in
  let* item = find t.items ~identifier in
  match item with
  | Note_item note ->
      let niceid_str = Data.Identifier.to_string (Data.Note.niceid note) in
      Error (Validation_error
        (Printf.sprintf "resolve applies only to todos, but %s is a note" niceid_str))
  | Todo_item todo ->
      let todo = Data.Todo.with_status todo Data.Todo.Done in
      TodoRepo.update t.todo_repo todo |> Result.map_error (map_repo_error ~entity_name:"todo")

let archive t ~identifier =
  let open Item_service in
  let open Result.Syntax in
  let* item = find t.items ~identifier in
  match item with
  | Todo_item todo ->
      let niceid_str = Data.Identifier.to_string (Data.Todo.niceid todo) in
      Error (Validation_error
        (Printf.sprintf "archive applies only to notes, but %s is a todo" niceid_str))
  | Note_item note ->
      let note = Data.Note.with_status note Data.Note.Archived in
      NoteRepo.update t.note_repo note |> Result.map_error (map_repo_error ~entity_name:"note")
