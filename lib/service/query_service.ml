module Note = Repository.Note
module Todo = Repository.Todo
module Result_data = Data.Result

type t = {
  note_repo : Note.t;
  todo_repo : Todo.t;
}

type error =
  | Repository_error of string
  | Validation_error of string

type item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

let init root = {
  note_repo = Repository.Root.note root;
  todo_repo = Repository.Root.todo root;
}

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
      Ok (sort_items items)

let show_by_niceid t niceid =
  match Todo.get_by_niceid t.todo_repo niceid with
  | Ok todo -> Ok (Todo_item todo)
  | Error (Todo.Not_found _) ->
      Note.get_by_niceid t.note_repo niceid
      |> Result.map (fun note -> Note_item note)
      |> Result.map_error (function
        | Note.Not_found _ ->
            Validation_error ("item not found: " ^ Data.Identifier.to_string niceid)
        | (Note.Backend_failure _ | Note.Duplicate_niceid _) as err ->
            repository_error_label err)
  | Error ((Todo.Backend_failure _ | Todo.Duplicate_niceid _) as err) ->
      Error (todo_repository_error_label err)

let show_todo_by_typeid t typeid =
  Todo.get t.todo_repo typeid
  |> Result.map (fun todo -> Todo_item todo)
  |> Result.map_error (function
    | Todo.Not_found _ ->
        Validation_error ("item not found: " ^ Data.Uuid.Typeid.to_string typeid)
    | (Todo.Backend_failure _ | Todo.Duplicate_niceid _) as err ->
        todo_repository_error_label err)

let show_note_by_typeid t typeid =
  Note.get t.note_repo typeid
  |> Result.map (fun note -> Note_item note)
  |> Result.map_error (function
    | Note.Not_found _ ->
        Validation_error ("item not found: " ^ Data.Uuid.Typeid.to_string typeid)
    | (Note.Backend_failure _ | Note.Duplicate_niceid _) as err ->
        repository_error_label err)

let show_by_typeid t typeid =
  match Data.Uuid.Typeid.get_prefix typeid with
  | "todo" -> show_todo_by_typeid t typeid
  | "note" -> show_note_by_typeid t typeid
  | prefix ->
      Error (Validation_error (Printf.sprintf "unknown typeid prefix %S" prefix))

let show t ~identifier =
  let try_niceid () =
    try Some (Data.Identifier.from_string identifier) with Invalid_argument _ -> None
  in
  let try_typeid () =
    try Some (Data.Uuid.Typeid.of_string identifier) with Invalid_argument _ -> None
  in
  match try_niceid (), try_typeid () with
  | Some niceid, _ -> show_by_niceid t niceid
  | _, Some typeid -> show_by_typeid t typeid
  | None, None ->
      Error (Validation_error (Printf.sprintf
        "invalid identifier %S — expected a niceid (e.g. kb-0) or typeid (e.g. todo_01abc...)"
        identifier))
