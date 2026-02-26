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

let try_parse ~from_string status =
  try Some (from_string status) with Invalid_argument _ -> None

let parse ~entity_name ~from_string status =
  match try_parse ~from_string status with
  | Some s -> Ok s
  | None ->
      Error (Validation_error (Printf.sprintf "invalid status \"%s\" for %s" status entity_name))

let list t ~entity_type ~statuses =
  let open Result.Syntax in
  let fetch_todos statuses =
    Todo.list t.todo_repo ~statuses
    |> Result.map_error (Item_service.map_repo_error ~entity_name:"todo")
  in
  let fetch_notes statuses =
    Note.list t.note_repo ~statuses
    |> Result.map_error (Item_service.map_repo_error ~entity_name:"note")
  in
  match entity_type with
  | Some "todo" ->
      let* todo_statuses =
        statuses
        |> List.map (parse ~entity_name:"todo" ~from_string:Data.Todo.status_from_string)
        |> Result_data.sequence
      in
      let+ todos = fetch_todos todo_statuses in
      todos |> List.map (fun todo -> Todo_item todo) |> sort_items
  | Some "note" ->
      let* note_statuses =
        statuses
        |> List.map (parse ~entity_name:"note" ~from_string:Data.Note.status_from_string)
        |> Result_data.sequence
      in
      let+ notes = fetch_notes note_statuses in
      notes |> List.map (fun note -> Note_item note) |> sort_items
  | Some other ->
      Error (Validation_error (Printf.sprintf "invalid entity type \"%s\"" other))
  | None ->
      let rec partition todo_statuses note_statuses = function
        | [] -> Ok (List.rev todo_statuses, List.rev note_statuses)
        | status :: rest -> (
            match try_parse ~from_string:Data.Todo.status_from_string status with
            | Some todo_status -> partition (todo_status :: todo_statuses) note_statuses rest
            | None -> (
                match try_parse ~from_string:Data.Note.status_from_string status with
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
      Ok (sort_items items)

let show t ~identifier =
  Item_service.find t.items ~identifier
