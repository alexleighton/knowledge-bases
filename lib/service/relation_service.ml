module RelationRepo = Repository.Relation

type relate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
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

let init root = {
  items         = Item_service.init root;
  relation_repo = Repository.Root.relation root;
}

let typeid_of_item = function
  | Item_service.Todo_item t -> Data.Todo.id t
  | Item_service.Note_item n -> Data.Note.id n

let niceid_of_item = function
  | Item_service.Todo_item t -> Data.Todo.niceid t
  | Item_service.Note_item n -> Data.Note.niceid n

let entity_type_of_item = function
  | Item_service.Todo_item _ -> "todo"
  | Item_service.Note_item _ -> "note"

let title_of_item = function
  | Item_service.Todo_item t -> Data.Todo.title t
  | Item_service.Note_item n -> Data.Note.title n

let map_relation_repo_error = function
  | RelationRepo.Duplicate ->
      Item_service.Validation_error "relation already exists"
  | RelationRepo.Backend_failure msg ->
      Item_service.Repository_error msg

let build_specs ~depends_on ~related_to ~uni ~bi =
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

let relate_many t ~source ~specs =
  let open Result.Syntax in
  let* source_item = Item_service.find t.items ~identifier:source in
  let source_typeid = typeid_of_item source_item in
  let source_niceid = niceid_of_item source_item in
  (* Validate phase: resolve all targets and parse all kinds before inserting *)
  let* resolved =
    List.map (fun spec ->
      let* target_item = Item_service.find t.items ~identifier:spec.target in
      let+ kind = Parse.relation_kind spec.kind in
      (target_item, kind, spec.bidirectional)
    ) specs
    |> Data.Result.sequence
  in
  (* Create phase: insert all relations *)
  List.map (fun (target_item, kind, bidirectional) ->
    let target_typeid = typeid_of_item target_item in
    let rel = Data.Relation.make ~source:source_typeid ~target:target_typeid
                ~kind ~bidirectional in
    let+ relation =
      RelationRepo.create t.relation_repo rel
      |> Result.map_error map_relation_repo_error
    in
    {
      relation;
      source_niceid;
      target_niceid = niceid_of_item target_item;
      target_type = entity_type_of_item target_item;
      target_title = title_of_item target_item;
    }
  ) resolved
  |> Data.Result.sequence

let relate t ~source ~target ~kind ~bidirectional =
  let open Result.Syntax in
  let specs = [{ target; kind; bidirectional }] in
  let+ results = relate_many t ~source ~specs in
  List.hd results
