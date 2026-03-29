module RelationRepo = Repository.Relation

type t = {
  items         : Item_service.t;
  relation_repo : RelationRepo.t;
}

type item = Data.Item.t =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

type relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  blocking    : bool option;
}

type show_result = {
  item     : item;
  outgoing : relation_entry list;
  incoming : relation_entry list;
}

let _map_relation_repo_error = Item_service.map_relation_repo_error

let init root = {
  items         = Item_service.init root;
  relation_repo = Repository.Root.relation root;
}

let _entry_of_rel items rel direction =
  let typeid = match direction with
    | `Outgoing -> Data.Relation.target rel
    | `Incoming -> Data.Relation.source rel
  in
  let blocking =
    if Data.Relation.is_blocking rel then
      Some true
    else
      None
  in
  let identifier = Data.Uuid.Typeid.to_string typeid in
  match Item_service.find items ~identifier with
  | Ok (Todo_item t) ->
      let blocking = match blocking with
        | Some true -> Some (Data.Todo.status t <> Data.Todo.Done)
        | other -> other
      in
      Some { kind = Data.Relation.kind rel;
             niceid = Data.Todo.niceid t;
             entity_type = "todo";
             title = Data.Todo.title t;
             blocking }
  | Ok (Note_item n) ->
      Some { kind = Data.Relation.kind rel;
             niceid = Data.Note.niceid n;
             entity_type = "note";
             title = Data.Note.title n;
             blocking = Option.map (fun _ -> false) blocking }
  | Error _ -> None

let show t ~identifier =
  let open Result.Syntax in
  let* item = Item_service.find t.items ~identifier in
  let typeid = Data.Item.typeid item in
  let* from_source =
    RelationRepo.find_by_source t.relation_repo typeid
    |> Result.map_error _map_relation_repo_error
  in
  let* from_target =
    RelationRepo.find_by_target t.relation_repo typeid
    |> Result.map_error _map_relation_repo_error
  in
  let outgoing =
    List.filter_map (fun rel ->
      _entry_of_rel t.items rel `Outgoing
    ) from_source
    @ List.filter_map (fun rel ->
        if Data.Relation.is_bidirectional rel then
          _entry_of_rel t.items rel `Incoming
        else None
      ) from_target
  in
  let incoming =
    List.filter_map (fun rel ->
      if not (Data.Relation.is_bidirectional rel) then
        _entry_of_rel t.items rel `Incoming
      else None
    ) from_target
  in
  Ok { item; outgoing; incoming }

let show_many t ~identifiers =
  Data.Result.traverse (fun id -> show t ~identifier:id) identifiers
