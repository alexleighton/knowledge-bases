module RelationRepo = Repository.Relation

type t = {
  items         : Item_service.t;
  relation_repo : RelationRepo.t;
}

type relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
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

let map_relation_repo_error = function
  | RelationRepo.Duplicate ->
      Item_service.Validation_error "relation already exists"
  | RelationRepo.Backend_failure msg ->
      Item_service.Repository_error msg

let parse_kind s =
  try Ok (Data.Relation_kind.make s)
  with Invalid_argument msg -> Error (Item_service.Validation_error msg)

let relate t ~source ~target ~kind ~bidirectional =
  let open Result.Syntax in
  let* source_item = Item_service.find t.items ~identifier:source in
  let* target_item = Item_service.find t.items ~identifier:target in
  let* kind = parse_kind kind in
  let source_typeid = typeid_of_item source_item in
  let target_typeid = typeid_of_item target_item in
  let rel = Data.Relation.make ~source:source_typeid ~target:target_typeid
              ~kind ~bidirectional in
  let+ relation =
    RelationRepo.create t.relation_repo rel
    |> Result.map_error map_relation_repo_error
  in
  {
    relation;
    source_niceid = niceid_of_item source_item;
    target_niceid = niceid_of_item target_item;
  }
