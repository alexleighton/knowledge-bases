type parsed_identifier = Item_service.parsed_identifier =
  | Niceid of Data.Identifier.t
  | Typeid of Data.Uuid.Typeid.t

let todo_status s =
  Data.Todo.status_of_string s
  |> Result.map_error (fun _ ->
       Item_service.Validation_error
         (Printf.sprintf "invalid status %S for todo" s))

let note_status s =
  Data.Note.status_of_string s
  |> Result.map_error (fun _ ->
       Item_service.Validation_error
         (Printf.sprintf "invalid status %S for note" s))

let relation_kind s =
  Data.Relation_kind.parse s
  |> Result.map_error (fun msg ->
       Item_service.Validation_error msg)

let entity_type s =
  match s with
  | "todo" | "note" -> Ok s
  | _ ->
      Error (Item_service.Validation_error
        (Printf.sprintf "invalid entity type %S" s))

let identifier = Item_service.parse_identifier
