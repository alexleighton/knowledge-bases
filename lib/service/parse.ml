type parsed_identifier =
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

let identifier s =
  match Data.Identifier.parse s with
  | Ok id -> Ok (Niceid id)
  | Error _ ->
      match Data.Uuid.Typeid.parse s with
      | Ok tid -> Ok (Typeid tid)
      | Error _ ->
          Error (Item_service.Validation_error
            (Printf.sprintf
              "invalid identifier %S — expected a niceid (e.g. kb-0) \
               or typeid (e.g. todo_01abc...)" s))
