module RelationRepo = Repository.Relation

type unrelate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
}

type relate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
  blocking      : bool;
}

type t = {
  items         : Item_service.t;
  relation_repo : RelationRepo.t;
}

type relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  target_type   : string;
  target_title  : Data.Title.t;
}

type unrelate_result = {
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  kind          : Data.Relation_kind.t;
  bidirectional : bool;
}

let map_relation_repo_error = Item_service.map_relation_repo_error

let init root = {
  items         = Item_service.init root;
  relation_repo = Repository.Root.relation root;
}

(* --- Relate operations --- *)

let build_specs ~depends_on ~related_to ~uni ~bi ~blocking =
  List.map (fun tgt ->
    { target = tgt; kind = "depends-on"; bidirectional = false;
      blocking = true })
    depends_on
  @ List.map (fun tgt ->
      { target = tgt; kind = "related-to"; bidirectional = true;
        blocking })
    related_to
  @ List.map (fun (k, tgt) ->
      { target = tgt; kind = k; bidirectional = false;
        blocking })
    uni
  @ List.map (fun (k, tgt) ->
      { target = tgt; kind = k; bidirectional = true;
        blocking })
    bi

let find_blockers t todo =
  let typeid = Data.Todo.id todo in
  match RelationRepo.find_by_source t.relation_repo typeid with
  | Error err -> Error (map_relation_repo_error err)
  | Ok rels ->
      let blocking = List.filter Data.Relation.is_blocking rels in
      let blockers =
        List.filter_map (fun rel ->
          let target_id = Data.Uuid.Typeid.to_string (Data.Relation.target rel) in
          match Item_service.find t.items ~identifier:target_id with
          | Ok (Item_service.Todo_item target_todo) ->
              if Data.Todo.status target_todo <> Data.Todo.Done then
                Some (Data.Identifier.to_string (Data.Todo.niceid target_todo))
              else None
          | Ok (Item_service.Note_item _) -> None
          | Error _ -> None
        ) blocking
      in
      Ok blockers

let list_unblocked_todos t ~todo_repo =
  let open Result.Syntax in
  let* todos =
    Repository.Todo.list todo_repo ~statuses:[Data.Todo.Open]
    |> Result.map_error Item_service.map_todo_repo_error
  in
  let rec go unblocked stuck = function
    | [] -> Ok (List.rev unblocked, stuck)
    | todo :: rest ->
        let* blockers = find_blockers t todo in
        if blockers = [] then go (todo :: unblocked) stuck rest
        else go unblocked (stuck + 1) rest
  in
  go [] 0 todos

let relate_many t ~source ~specs =
  let open Result.Syntax in
  let* source_item = Item_service.find t.items ~identifier:source in
  let source_typeid = Data.Item.typeid source_item in
  let source_niceid = Data.Item.niceid source_item in
  (* Validate phase: resolve all targets and parse all kinds before inserting *)
  let* resolved =
    Data.Result.traverse (fun (spec : relate_spec) ->
      let* target_item = Item_service.find t.items ~identifier:spec.target in
      let+ kind = Parse.relation_kind spec.kind in
      (target_item, kind, spec.bidirectional, spec.blocking)
    ) specs
  in
  (* Create phase: insert all relations *)
  Data.Result.traverse (fun (target_item, kind, bidirectional, blocking) ->
    let target_typeid = Data.Item.typeid target_item in
    let rel = Data.Relation.make ~source:source_typeid ~target:target_typeid
                ~kind ~bidirectional ~blocking in
    let+ relation =
      RelationRepo.create t.relation_repo rel
      |> Result.map_error map_relation_repo_error
    in
    {
      relation;
      source_niceid;
      target_niceid = Data.Item.niceid target_item;
      target_type = Data.Item.entity_type target_item;
      target_title = Data.Item.title target_item;
    }
  ) resolved

let relate t ~source ~target ~kind ~bidirectional ~blocking =
  let open Result.Syntax in
  let specs = [{ target; kind; bidirectional; blocking }] in
  let+ results = relate_many t ~source ~specs in
  List.hd results

(* --- Unrelate operations --- *)

let build_unrelate_specs ~depends_on ~related_to ~uni ~bi =
  List.map (fun tgt ->
    { target = tgt; kind = "depends-on"; bidirectional = false })
    depends_on
  @ List.map (fun tgt ->
      { target = tgt; kind = "related-to"; bidirectional = true })
    related_to
  @ List.map (fun (k, tgt) ->
      { target = tgt; kind = k; bidirectional = false })
    uni
  @ List.map (fun (k, tgt) ->
      { target = tgt; kind = k; bidirectional = true })
    bi

let unrelate_many t ~source ~specs =
  let open Result.Syntax in
  let* source_item = Item_service.find t.items ~identifier:source in
  let source_typeid = Data.Item.typeid source_item in
  let source_niceid = Data.Item.niceid source_item in
  let* resolved =
    Data.Result.traverse (fun (spec : unrelate_spec) ->
      let* target_item = Item_service.find t.items ~identifier:spec.target in
      let+ kind = Parse.relation_kind spec.kind in
      (target_item, kind, spec.bidirectional)
    ) specs
  in
  Data.Result.traverse (fun (target_item, kind, bidirectional) ->
    let target_typeid = Data.Item.typeid target_item in
    let+ () =
      RelationRepo.delete t.relation_repo ~source:source_typeid
        ~target:target_typeid ~kind ~bidirectional
      |> Result.map_error map_relation_repo_error
    in
    {
      source_niceid;
      target_niceid = Data.Item.niceid target_item;
      kind;
      bidirectional;
    }
  ) resolved
