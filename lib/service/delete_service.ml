module TodoRepo = Repository.Todo
module NoteRepo = Repository.Note
module RelationRepo = Repository.Relation
module NiceidRepo = Repository.Niceid

type t = {
  items         : Item_service.t;
  todo_repo     : TodoRepo.t;
  note_repo     : NoteRepo.t;
  relation_repo : RelationRepo.t;
  niceid_repo   : NiceidRepo.t;
}

type delete_result = {
  niceid            : Data.Identifier.t;
  entity_type       : string;
  relations_removed : int;
}

type delete_error =
  | Blocked_dependency of { niceid : string; dependents : string list }
  | Service_error of Item_service.error

let init root = {
  items         = Item_service.init root;
  todo_repo     = Repository.Root.todo root;
  note_repo     = Repository.Root.note root;
  relation_repo = Repository.Root.relation root;
  niceid_repo   = Repository.Root.niceid root;
}

let _to_service_error map e = Service_error (map e)

let cascade_delete ~todo_repo ~note_repo ~relation_repo ~niceid_repo
    ~map_err ~typeid ~niceid ~entity_type =
  let open Result.Syntax in
  let* relations_removed =
    RelationRepo.delete_by_entity relation_repo typeid
    |> Result.map_error (fun e -> map_err (`Rel e))
  in
  let* () =
    NiceidRepo.delete niceid_repo typeid
    |> Result.map_error (fun e -> map_err (`Niceid e))
  in
  let+ () =
    match entity_type with
    | "todo" -> TodoRepo.delete todo_repo niceid
                |> Result.map_error (fun e -> map_err (`Todo e))
    | _ ->      NoteRepo.delete note_repo niceid
                |> Result.map_error (fun e -> map_err (`Note e))
  in
  relations_removed

let _find_blocking_dependents t typeid =
  let open Result.Syntax in
  let* incoming =
    RelationRepo.find_by_target t.relation_repo typeid
    |> Result.map_error (_to_service_error Item_service.map_relation_repo_error)
  in
  let blocking = List.filter Data.Relation.is_blocking incoming in
  let+ dependents =
    List.filter_map (fun rel ->
      let source_id = Data.Uuid.Typeid.to_string (Data.Relation.source rel) in
      match Item_service.find t.items ~identifier:source_id with
      | Ok (Item_service.Todo_item todo) ->
          if Data.Todo.status todo <> Data.Todo.Done then
            Some (Ok (Data.Identifier.to_string (Data.Todo.niceid todo)))
          else None
      | Ok (Item_service.Note_item _) -> None
      | Error _ -> None
    ) blocking
    |> Data.Result.sequence
  in
  dependents

let _map_cascade_err = function
  | `Todo e -> _to_service_error Item_service.map_todo_repo_error e
  | `Note e -> _to_service_error Item_service.map_note_repo_error e
  | `Rel e -> _to_service_error Item_service.map_relation_repo_error e
  | `Niceid e -> _to_service_error Item_service.map_niceid_repo_error e

let _delete_item t item =
  let open Result.Syntax in
  let typeid = Data.Item.typeid item in
  let niceid = Data.Item.niceid item in
  let entity_type = Data.Item.entity_type item in
  let+ relations_removed =
    cascade_delete
      ~todo_repo:t.todo_repo ~note_repo:t.note_repo
      ~relation_repo:t.relation_repo ~niceid_repo:t.niceid_repo
      ~map_err:_map_cascade_err ~typeid ~niceid ~entity_type
  in
  { niceid; entity_type; relations_removed }

let delete_many t ~identifiers ~force =
  let open Result.Syntax in
  (* Phase 1: resolve all items and check blocking *)
  let* resolved =
    Data.Result.traverse (fun identifier ->
      let* item =
        Item_service.find t.items ~identifier
        |> Result.map_error (fun e -> Service_error e)
      in
      let typeid = Data.Item.typeid item in
      let niceid_str = Data.Identifier.to_string (Data.Item.niceid item) in
      let+ () =
        if force then Ok ()
        else
          let* dependents = _find_blocking_dependents t typeid in
          if dependents <> [] then
            Error (Blocked_dependency { niceid = niceid_str; dependents })
          else Ok ()
      in
      item
    ) identifiers
  in
  (* Phase 2: delete all *)
  Data.Result.traverse (fun item -> _delete_item t item) resolved
