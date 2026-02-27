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
            match status with
            | None -> Ok todo
            | Some s -> let+ s = Parse.todo_status s in Data.Todo.with_status todo s
          in
          let todo = match title with None -> todo | Some t -> Data.Todo.with_title todo t in
          let todo = match content with None -> todo | Some c -> Data.Todo.with_content todo c in
          let+ todo = TodoRepo.update t.todo_repo todo |> Result.map_error map_todo_repo_error in
          Todo_item todo
      | Note_item note ->
          let* note =
            match status with
            | None -> Ok note
            | Some s -> let+ s = Parse.note_status s in Data.Note.with_status note s
          in
          let note = match title with None -> note | Some t -> Data.Note.with_title note t in
          let note = match content with None -> note | Some c -> Data.Note.with_content note c in
          let+ note = NoteRepo.update t.note_repo note |> Result.map_error map_note_repo_error in
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
      TodoRepo.update t.todo_repo todo |> Result.map_error map_todo_repo_error

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
      NoteRepo.update t.note_repo note |> Result.map_error map_note_repo_error
