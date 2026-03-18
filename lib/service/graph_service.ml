module RelationRepo = Repository.Relation
module Typeid = Data.Uuid.Typeid

type t = {
  relation_repo : RelationRepo.t;
}

type direction = Outgoing | Incoming | Any

let init root = {
  relation_repo = Repository.Root.relation root;
}

let _map_err e = Item_service.map_relation_repo_error e

let _matches_kind filter rel =
  match filter with
  | None -> true
  | Some k -> Data.Relation_kind.to_string (Data.Relation.kind rel)
              = Data.Relation_kind.to_string k

module TypeidSet = Typeid.Set

let _neighbors t ~typeid ~kind ~direction =
  let open Result.Syntax in
  let* outgoing =
    match direction with
    | Incoming -> Ok []
    | Outgoing | Any ->
        RelationRepo.find_by_source t.relation_repo typeid
        |> Result.map_error _map_err
  in
  let* incoming =
    match direction with
    | Outgoing -> Ok []
    | Incoming | Any ->
        RelationRepo.find_by_target t.relation_repo typeid
        |> Result.map_error _map_err
  in
  let extract_targets rels =
    List.filter_map (fun rel ->
      if _matches_kind kind rel then Some (Data.Relation.target rel)
      else None
    ) rels
  in
  let extract_sources rels =
    List.filter_map (fun rel ->
      if _matches_kind kind rel then Some (Data.Relation.source rel)
      else None
    ) rels
  in
  let bidi_targets rels =
    List.filter_map (fun rel ->
      if _matches_kind kind rel && Data.Relation.is_bidirectional rel then
        Some (Data.Relation.source rel)
      else None
    ) rels
  in
  let bidi_sources rels =
    List.filter_map (fun rel ->
      if _matches_kind kind rel && Data.Relation.is_bidirectional rel then
        Some (Data.Relation.target rel)
      else None
    ) rels
  in
  let neighbors =
    extract_targets outgoing
    @ extract_sources incoming
    @ (match direction with
       | Any -> bidi_targets incoming @ bidi_sources outgoing
       | Outgoing -> bidi_sources outgoing
       | Incoming -> bidi_targets incoming)
  in
  Ok neighbors

let reachable_from t ~typeid ~kind ~direction =
  let open Result.Syntax in
  let visited = ref (TypeidSet.singleton typeid) in
  let queue = Queue.create () in
  Queue.push typeid queue;
  let result = ref [] in
  let rec loop () =
    if Queue.is_empty queue then Ok ()
    else
      let current = Queue.pop queue in
      let* neighbors = _neighbors t ~typeid:current ~kind ~direction in
      List.iter (fun n ->
        if not (TypeidSet.mem n !visited) then begin
          visited := TypeidSet.add n !visited;
          result := n :: !result;
          Queue.push n queue
        end
      ) neighbors;
      loop ()
  in
  let+ () = loop () in
  List.rev !result

let connected_component t ~typeid =
  let open Result.Syntax in
  let+ reachable = reachable_from t ~typeid ~kind:None ~direction:Any in
  typeid :: reachable
