module Note = Repository.Note
module Todo = Repository.Todo
module Result_data = Data.Result

type t = {
  items     : Item_service.t;
  note_repo : Note.t;
  todo_repo : Todo.t;
}

type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

type item = Item_service.item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

let init root = {
  items     = Item_service.init root;
  note_repo = Repository.Root.note root;
  todo_repo = Repository.Root.todo root;
}

let raw_id_of_item = function
  | Todo_item todo -> Data.Identifier.raw_id (Data.Todo.niceid todo)
  | Note_item note -> Data.Identifier.raw_id (Data.Note.niceid note)

let sort_items items =
  List.sort (fun a b -> Int.compare (raw_id_of_item a) (raw_id_of_item b)) items

let list t ~entity_type ~statuses =
  let open Result.Syntax in
  let try_parse_todo status =
    try Some (Data.Todo.status_from_string status) with Invalid_argument _ -> None
  in
  let try_parse_note status =
    try Some (Data.Note.status_from_string status) with Invalid_argument _ -> None
  in
  let try_parse_status status =
    match try_parse_todo status with
    | Some s -> `Todo s
    | None ->
      match try_parse_note status with
      | Some s -> `Note s
      | None -> `Invalid status
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
    Todo.list t.todo_repo ~statuses |> Result.map_error Item_service.map_todo_repo_error
  in
  let fetch_notes statuses =
    Note.list t.note_repo ~statuses |> Result.map_error Item_service.map_note_repo_error
  in
  match entity_type with
  | Some "todo" ->
      let* todo_statuses = Result_data.sequence (List.map parse_todo statuses) in
      let+ todos = fetch_todos todo_statuses in
      todos |> List.map (fun todo -> Todo_item todo) |> sort_items
  | Some "note" ->
      let* note_statuses = Result_data.sequence (List.map parse_note statuses) in
      let+ notes = fetch_notes note_statuses in
      notes |> List.map (fun note -> Note_item note) |> sort_items
  | Some other ->
      Error (Validation_error (Printf.sprintf "invalid entity type \"%s\"" other))
  | None ->
      let rec partition todo_statuses note_statuses = function
        | [] -> Ok (List.rev todo_statuses, List.rev note_statuses)
        | status :: rest ->
          match try_parse_status status with
          | `Todo s -> partition (s :: todo_statuses) note_statuses rest
          | `Note s -> partition todo_statuses (s :: note_statuses) rest
          | `Invalid s ->
              Error (Validation_error (Printf.sprintf "invalid status \"%s\"" s))
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
      Ok (sort_items items)

let show t ~identifier =
  Item_service.find t.items ~identifier
