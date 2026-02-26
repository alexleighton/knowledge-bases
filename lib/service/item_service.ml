module Note = Repository.Note
module Todo = Repository.Todo

type error =
  | Repository_error of string
  | Validation_error of string

type item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

type t = {
  note_repo : Note.t;
  todo_repo : Todo.t;
}

let init root = {
  note_repo = Repository.Root.note root;
  todo_repo = Repository.Root.todo root;
}

let map_note_repo_error = function
  | Note.Backend_failure msg -> Repository_error msg
  | Note.Duplicate_niceid niceid ->
      Repository_error ("duplicate nice id " ^ Data.Identifier.to_string niceid)
  | Note.Not_found _ -> Repository_error "note not found"

let map_todo_repo_error = function
  | Todo.Backend_failure msg -> Repository_error msg
  | Todo.Duplicate_niceid niceid ->
      Repository_error ("duplicate nice id " ^ Data.Identifier.to_string niceid)
  | Todo.Not_found _ -> Repository_error "todo not found"

let find_by_niceid t niceid =
  match Todo.get_by_niceid t.todo_repo niceid with
  | Ok todo -> Ok (Todo_item todo)
  | Error (Todo.Not_found _) ->
      Note.get_by_niceid t.note_repo niceid
      |> Result.map (fun note -> Note_item note)
      |> Result.map_error (function
        | Note.Not_found _ ->
            Validation_error ("item not found: " ^ Data.Identifier.to_string niceid)
        | (Note.Backend_failure _ | Note.Duplicate_niceid _) as err ->
            map_note_repo_error err)
  | Error ((Todo.Backend_failure _ | Todo.Duplicate_niceid _) as err) ->
      Error (map_todo_repo_error err)

let find_todo_by_typeid t typeid =
  Todo.get t.todo_repo typeid
  |> Result.map (fun todo -> Todo_item todo)
  |> Result.map_error (function
    | Todo.Not_found _ ->
        Validation_error ("item not found: " ^ Data.Uuid.Typeid.to_string typeid)
    | (Todo.Backend_failure _ | Todo.Duplicate_niceid _) as err ->
        map_todo_repo_error err)

let find_note_by_typeid t typeid =
  Note.get t.note_repo typeid
  |> Result.map (fun note -> Note_item note)
  |> Result.map_error (function
    | Note.Not_found _ ->
        Validation_error ("item not found: " ^ Data.Uuid.Typeid.to_string typeid)
    | (Note.Backend_failure _ | Note.Duplicate_niceid _) as err ->
        map_note_repo_error err)

let find_by_typeid t typeid =
  match Data.Uuid.Typeid.get_prefix typeid with
  | "todo" -> find_todo_by_typeid t typeid
  | "note" -> find_note_by_typeid t typeid
  | prefix ->
      Error (Validation_error (Printf.sprintf "unknown typeid prefix %S" prefix))

let find t ~identifier =
  let try_niceid () =
    try Some (Data.Identifier.from_string identifier) with Invalid_argument _ -> None
  in
  let try_typeid () =
    try Some (Data.Uuid.Typeid.of_string identifier) with Invalid_argument _ -> None
  in
  match try_niceid (), try_typeid () with
  | Some niceid, _ -> find_by_niceid t niceid
  | _, Some typeid -> find_by_typeid t typeid
  | None, None ->
      Error (Validation_error (Printf.sprintf
        "invalid identifier %S — expected a niceid (e.g. kb-0) or typeid (e.g. todo_01abc...)"
        identifier))
