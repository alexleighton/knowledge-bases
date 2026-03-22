module RelationRepo = Repository.Relation

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

let map_relation_repo_error = Item_service.map_relation_repo_error

let init root = {
  items         = Item_service.init root;
  relation_repo = Repository.Root.relation root;
}

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

let relate_many t ~source ~specs =
  let open Result.Syntax in
  let* source_item = Item_service.find t.items ~identifier:source in
  let source_typeid = Data.Item.typeid source_item in
  let source_niceid = Data.Item.niceid source_item in
  (* Validate phase: resolve all targets and parse all kinds before inserting *)
  let* resolved =
    List.map (fun spec ->
      let* target_item = Item_service.find t.items ~identifier:spec.target in
      let+ kind = Parse.relation_kind spec.kind in
      (target_item, kind, spec.bidirectional, spec.blocking)
    ) specs
    |> Data.Result.sequence
  in
  (* Create phase: insert all relations *)
  List.map (fun (target_item, kind, bidirectional, blocking) ->
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
  |> Data.Result.sequence

let relate t ~source ~target ~kind ~bidirectional ~blocking =
  let open Result.Syntax in
  let specs = [{ target; kind; bidirectional; blocking }] in
  let+ results = relate_many t ~source ~specs in
  List.hd results

type unrelate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
}

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

type unrelate_result = {
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  kind          : Data.Relation_kind.t;
  bidirectional : bool;
}

let unrelate_many t ~source ~specs =
  let open Result.Syntax in
  let* source_item = Item_service.find t.items ~identifier:source in
  let source_typeid = Data.Item.typeid source_item in
  let source_niceid = Data.Item.niceid source_item in
  let* resolved =
    List.map (fun (spec : unrelate_spec) ->
      let* target_item = Item_service.find t.items ~identifier:spec.target in
      let+ kind = Parse.relation_kind spec.kind in
      (target_item, kind, spec.bidirectional)
    ) specs
    |> Data.Result.sequence
  in
  List.map (fun (target_item, kind, bidirectional) ->
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
  |> Data.Result.sequence
