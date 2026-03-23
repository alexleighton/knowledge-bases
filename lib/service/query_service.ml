module Note = Repository.Note
module Todo = Repository.Todo
module RelationRepo = Repository.Relation
module Result_data = Data.Result

type t = {
  items         : Item_service.t;
  note_repo     : Note.t;
  todo_repo     : Todo.t;
  relation_repo : RelationRepo.t;
  relation_svc  : Relation_service.t;
  graph_svc     : Graph_service.t;
}

type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

type item = Data.Item.t =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

type sort_order = Sort_created | Sort_updated

type relation_filter = {
  target    : string;
  kind      : string;
  direction : Graph_service.direction;
}

type list_spec = {
  entity_type      : string option;
  statuses         : string list;
  available        : bool;
  sort             : sort_order option;
  ascending        : bool;
  count_only       : bool;
  relation_filters : relation_filter list;
  transitive       : bool;
  blocked          : bool;
}

type list_result =
  | Items of item list
  | Counts of { todos : (string * int) list; notes : (string * int) list }

let build_filters ~depends_on ~related_to ~uni ~bi =
  List.map (fun tgt ->
    { target = tgt; kind = "depends-on"; direction = Graph_service.Outgoing }
  ) depends_on
  @ List.map (fun tgt ->
      { target = tgt; kind = "related-to"; direction = Graph_service.Any }
    ) related_to
  @ List.map (fun (k, tgt) ->
      { target = tgt; kind = k; direction = Graph_service.Outgoing }
    ) uni
  @ List.map (fun (k, tgt) ->
      { target = tgt; kind = k; direction = Graph_service.Any }
    ) bi

let default_list_spec = {
  entity_type      = None;
  statuses         = [];
  available        = false;
  sort             = None;
  ascending        = true;
  count_only       = false;
  relation_filters = [];
  transitive       = false;
  blocked          = false;
}

let _map_relation_repo_error = Item_service.map_relation_repo_error

let init root = {
  items         = Item_service.init root;
  note_repo     = Repository.Root.note root;
  todo_repo     = Repository.Root.todo root;
  relation_repo = Repository.Root.relation root;
  relation_svc  = Relation_service.init root;
  graph_svc     = Graph_service.init root;
}

(* --- Sorting --- *)

let _sort_items spec items =
  match spec.sort with
  | None ->
      let cmp a b = Int.compare
        (Data.Identifier.raw_id (Data.Item.niceid a))
        (Data.Identifier.raw_id (Data.Item.niceid b)) in
      let cmp = if spec.ascending then cmp else fun a b -> cmp b a in
      List.sort cmp items
  | Some Sort_created ->
      let cmp a b = Data.Timestamp.compare (Data.Item.created_at a) (Data.Item.created_at b) in
      let cmp = if spec.ascending then cmp else fun a b -> cmp b a in
      List.sort cmp items
  | Some Sort_updated ->
      let cmp a b = Data.Timestamp.compare (Data.Item.updated_at a) (Data.Item.updated_at b) in
      let cmp = if spec.ascending then cmp else fun a b -> cmp b a in
      List.sort cmp items

(* --- Counting --- *)

let _status_of_item = function
  | Todo_item t -> Data.Todo.status_to_string (Data.Todo.status t)
  | Note_item n -> Data.Note.status_to_string (Data.Note.status n)

let _count_items items =
  let todo_counts = Hashtbl.create 4 in
  let note_counts = Hashtbl.create 4 in
  List.iter (fun item ->
    let status = _status_of_item item in
    let tbl = match item with Todo_item _ -> todo_counts | Note_item _ -> note_counts in
    let cur = try Hashtbl.find tbl status with Not_found -> 0 in
    Hashtbl.replace tbl status (cur + 1)
  ) items;
  let to_list tbl =
    Hashtbl.fold (fun k v acc -> (k, v) :: acc) tbl []
    |> List.sort (fun (a, _) (b, _) -> String.compare a b)
  in
  Counts { todos = to_list todo_counts; notes = to_list note_counts }

(* --- Listing internals --- *)

let _list_available t =
  let open Result.Syntax in
  let* todos =
    Todo.list t.todo_repo ~statuses:[Data.Todo.Open]
    |> Result.map_error Item_service.map_todo_repo_error
  in
  let rec filter_unblocked acc = function
    | [] -> Ok (List.rev acc)
    | todo :: rest ->
        let* blockers = Relation_service.find_blockers t.relation_svc todo in
        if blockers = [] then filter_unblocked (todo :: acc) rest
        else filter_unblocked acc rest
  in
  let* unblocked = filter_unblocked [] todos in
  Ok (List.map (fun todo -> Todo_item todo) unblocked)

let _fetch_items t ~entity_type ~statuses =
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
      List.map (fun todo -> Todo_item todo) todos
  | Some "note" ->
      let* note_statuses = Result_data.sequence (List.map Parse.note_status statuses) in
      let+ notes = fetch_notes note_statuses in
      List.map (fun note -> Note_item note) notes
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
      let+ notes =
        if should_query_notes then fetch_notes note_statuses else Ok []
      in
      (List.map (fun todo -> Todo_item todo) todos)
      @ (List.map (fun note -> Note_item note) notes)

(* --- Relation filtering --- *)

module TypeidSet = Data.Uuid.Typeid.Set

let _apply_relation_filters t spec items =
  if spec.relation_filters = [] then Ok items
  else
  let open Result.Syntax in
  let* allowed_sets =
    List.map (fun (rf : relation_filter) ->
      let* target_item = Item_service.find t.items ~identifier:rf.target in
      let target_typeid = Data.Item.typeid target_item in
      let* kind = Parse.relation_kind rf.kind in
      if spec.transitive then
        let+ reachable =
          Graph_service.reachable_from t.graph_svc ~typeid:target_typeid
            ~kind:(Some kind) ~direction:rf.direction
        in
        let set = List.fold_left (fun s id -> TypeidSet.add id s) TypeidSet.empty reachable in
        TypeidSet.add target_typeid set
      else
        let* rels =
          match rf.direction with
          | Graph_service.Outgoing ->
              RelationRepo.find_by_source t.relation_repo target_typeid
              |> Result.map_error _map_relation_repo_error
          | Graph_service.Incoming ->
              RelationRepo.find_by_target t.relation_repo target_typeid
              |> Result.map_error _map_relation_repo_error
          | Graph_service.Any ->
              let* out = RelationRepo.find_by_source t.relation_repo target_typeid
                         |> Result.map_error _map_relation_repo_error in
              let+ inc = RelationRepo.find_by_target t.relation_repo target_typeid
                         |> Result.map_error _map_relation_repo_error in
              out @ inc
        in
        let matching = List.filter (fun rel ->
          Data.Relation_kind.to_string (Data.Relation.kind rel)
          = Data.Relation_kind.to_string kind
        ) rels in
        let ids = List.map (fun rel ->
          match rf.direction with
          | Graph_service.Outgoing -> Data.Relation.target rel
          | Graph_service.Incoming -> Data.Relation.source rel
          | Graph_service.Any ->
              let src = Data.Relation.source rel in
              let tgt = Data.Relation.target rel in
              if Data.Uuid.Typeid.to_string src = Data.Uuid.Typeid.to_string target_typeid
              then tgt else src
        ) matching in
        Ok (List.fold_left (fun s id -> TypeidSet.add id s) TypeidSet.empty ids)
    ) spec.relation_filters
    |> Result_data.sequence
  in
  let combined = match allowed_sets with
    | [] -> TypeidSet.empty
    | first :: rest -> List.fold_left TypeidSet.inter first rest
  in
  Ok (List.filter (fun item ->
    TypeidSet.mem (Data.Item.typeid item) combined
  ) items)

(* --- Blocked filtering --- *)

let _filter_blocked t items =
  let open Result.Syntax in
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
        match item with
        | Todo_item todo ->
            let* blockers = Relation_service.find_blockers t.relation_svc todo in
            if blockers <> [] then go (item :: acc) rest
            else go acc rest
        | Note_item _ -> go acc rest
  in
  go [] items

(* --- Main list function --- *)

let _validate_spec spec =
  if spec.available && spec.entity_type = Some "note" then
    Error (Validation_error "--available applies only to todos, not notes")
  else if spec.available && spec.statuses <> [] then
    Error (Validation_error "--available cannot be combined with --status")
  else if spec.available && spec.blocked then
    Error (Validation_error "--available cannot be combined with --blocked")
  else if spec.sort <> None && spec.count_only then
    Error (Validation_error "--sort cannot be combined with --count")
  else if spec.transitive && List.length spec.relation_filters <> 1 then
    Error (Validation_error "--transitive requires exactly one relation filter")
  else Ok ()

let list t spec =
  let open Result.Syntax in
  let* () = _validate_spec spec in
  let* items =
    if spec.available then _list_available t
    else _fetch_items t ~entity_type:spec.entity_type ~statuses:spec.statuses
  in
  let* items = _apply_relation_filters t spec items in
  let* items = if spec.blocked then _filter_blocked t items else Ok items in
  let items = _sort_items spec items in
  if spec.count_only then Ok (_count_items items)
  else Ok (Items items)
