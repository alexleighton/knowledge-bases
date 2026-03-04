module Note = Repository.Note
module Todo = Repository.Todo
module RelationRepo = Repository.Relation
module Result_data = Data.Result

type t = {
  items         : Item_service.t;
  note_repo     : Note.t;
  todo_repo     : Todo.t;
  relation_repo : RelationRepo.t;
}

type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

type item = Item_service.item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

type relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
}

type show_result = {
  item     : item;
  outgoing : relation_entry list;
  incoming : relation_entry list;
}

let init root = {
  items         = Item_service.init root;
  note_repo     = Repository.Root.note root;
  todo_repo     = Repository.Root.todo root;
  relation_repo = Repository.Root.relation root;
}

let raw_id_of_item = function
  | Todo_item todo -> Data.Identifier.raw_id (Data.Todo.niceid todo)
  | Note_item note -> Data.Identifier.raw_id (Data.Note.niceid note)

let sort_items items =
  List.sort (fun a b -> Int.compare (raw_id_of_item a) (raw_id_of_item b)) items

let list t ~entity_type ~statuses =
  let open Result.Syntax in
  let try_parse_status status =
    match Data.Todo.status_of_string status with
    | Ok s -> `Todo s
    | Error _ ->
        match Data.Note.status_of_string status with
        | Ok s -> `Note s
        | Error _ -> `Invalid status
  in
  let fetch_todos statuses =
    Todo.list t.todo_repo ~statuses |> Result.map_error Item_service.map_todo_repo_error
  in
  let fetch_notes statuses =
    Note.list t.note_repo ~statuses |> Result.map_error Item_service.map_note_repo_error
  in
  match entity_type with
  | Some "todo" ->
      let* todo_statuses = Result_data.sequence (List.map Parse.todo_status statuses) in
      let+ todos = fetch_todos todo_statuses in
      todos |> List.map (fun todo -> Todo_item todo) |> sort_items
  | Some "note" ->
      let* note_statuses = Result_data.sequence (List.map Parse.note_status statuses) in
      let+ notes = fetch_notes note_statuses in
      notes |> List.map (fun note -> Note_item note) |> sort_items
  | Some other ->
      let+ _ = Parse.entity_type other in
      []
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

let _typeid_of_item = function
  | Todo_item t -> Data.Todo.id t
  | Note_item n -> Data.Note.id n

let _entry_of_typeid items typeid rel_kind =
  let identifier = Data.Uuid.Typeid.to_string typeid in
  match Item_service.find items ~identifier with
  | Ok (Todo_item t) ->
      Some { kind = rel_kind;
             niceid = Data.Todo.niceid t;
             entity_type = "todo";
             title = Data.Todo.title t }
  | Ok (Note_item n) ->
      Some { kind = rel_kind;
             niceid = Data.Note.niceid n;
             entity_type = "note";
             title = Data.Note.title n }
  | Error _ -> None

let _map_relation_repo_error = function
  | RelationRepo.Duplicate -> Item_service.Validation_error "unexpected"
  | RelationRepo.Backend_failure msg -> Item_service.Repository_error msg

let show t ~identifier =
  let open Result.Syntax in
  let* item = Item_service.find t.items ~identifier in
  let typeid = _typeid_of_item item in
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
      _entry_of_typeid t.items (Data.Relation.target rel) (Data.Relation.kind rel)
    ) from_source
    @ List.filter_map (fun rel ->
        if Data.Relation.is_bidirectional rel then
          _entry_of_typeid t.items (Data.Relation.source rel) (Data.Relation.kind rel)
        else None
      ) from_target
  in
  let incoming =
    List.filter_map (fun rel ->
      if not (Data.Relation.is_bidirectional rel) then
        _entry_of_typeid t.items (Data.Relation.source rel) (Data.Relation.kind rel)
      else None
    ) from_target
  in
  Ok { item; outgoing; incoming }

let show_many t ~identifiers =
  let open Result.Syntax in
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | id :: rest ->
        let* result = show t ~identifier:id in
        go (result :: acc) rest
  in
  go [] identifiers
