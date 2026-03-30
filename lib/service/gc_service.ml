module TodoRepo = Repository.Todo
module NoteRepo = Repository.Note
module RelationRepo = Repository.Relation
module NiceidRepo = Repository.Niceid
module TypeidSet = Data.Uuid.Typeid.Set

type t = {
  todo_repo     : TodoRepo.t;
  note_repo     : NoteRepo.t;
  relation_repo : RelationRepo.t;
  niceid_repo   : NiceidRepo.t;
  graph_svc     : Graph_service.t;
  config_svc    : Config_service.t;
}

type gc_item = {
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  age_days    : int;
}

type gc_result = {
  items_removed     : int;
  relations_removed : int;
}

type candidate = {
  typeid      : Data.Uuid.Typeid.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  updated_at  : Data.Timestamp.t;
}

let default_max_age_seconds = int_of_string Config_service.default_gc_max_age

let parse_age s =
  match int_of_string_opt s with
  | Some n when n >= 0 -> Some n
  | _ -> None

(* --- Internal helpers --- *)

let _resolve_max_age t =
  match Config_service.get t.config_svc "gc_max_age" with
  | Ok { Config_service.value; _ } ->
      (match parse_age value with Some v -> v | None -> default_max_age_seconds)
  | Error _ -> default_max_age_seconds

let _candidates_of (type a s)
    (module E : Data.Entity.S with type t = a and type status = s) ~cutoff entities =
  List.filter_map (fun entity ->
    let updated = E.updated_at entity in
    if Data.Timestamp.to_epoch updated <= cutoff then
      Some { typeid = E.id entity; niceid = E.niceid entity;
             entity_type = E.entity_name; title = E.title entity;
             updated_at = updated }
    else None
  ) entities

let _list_terminal_candidates t ~max_age_seconds ~now =
  let open Result.Syntax in
  let cutoff = now - max_age_seconds in
  let* done_todos =
    TodoRepo.list t.todo_repo ~statuses:[Data.Todo.Done]
    |> Result.map_error Item_service.map_todo_repo_error
  in
  let+ archived_notes =
    NoteRepo.list t.note_repo ~statuses:[Data.Note.Archived]
    |> Result.map_error Item_service.map_note_repo_error
  in
  _candidates_of (module Data.Todo) ~cutoff done_todos
  @ _candidates_of (module Data.Note) ~cutoff archived_notes

(* Filter candidates: only keep those in components where ALL members are
   terminal and age-eligible *)
let _filter_by_component t candidates =
  let open Result.Syntax in
  let candidate_set =
    List.fold_left (fun s c -> TypeidSet.add c.typeid s) TypeidSet.empty candidates
  in
  let visited = ref TypeidSet.empty in
  let eligible = ref [] in
  let* () =
    List.fold_left (fun acc cand ->
      let* () = acc in
      if TypeidSet.mem cand.typeid !visited then Ok ()
      else
        let* component =
          Graph_service.connected_component t.graph_svc ~typeid:cand.typeid
        in
        let comp_set =
          List.fold_left (fun s id -> TypeidSet.add id s) TypeidSet.empty component
        in
        visited := TypeidSet.union !visited comp_set;
        (* Check if all component members are in the candidate set *)
        let all_eligible = TypeidSet.for_all
          (fun id -> TypeidSet.mem id candidate_set) comp_set
        in
        if all_eligible then
          eligible := List.filter (fun c ->
            TypeidSet.mem c.typeid comp_set
          ) candidates @ !eligible;
        Ok ()
    ) (Ok ()) candidates
  in
  Ok (List.rev !eligible)

let _map_cascade_err = function
  | `Todo e -> Item_service.map_todo_repo_error e
  | `Note e -> Item_service.map_note_repo_error e
  | `Rel e -> Item_service.map_relation_repo_error e
  | `Niceid e -> Item_service.map_niceid_repo_error e

let _delete_candidate t cand =
  Delete_service.cascade_delete
    ~todo_repo:t.todo_repo ~note_repo:t.note_repo
    ~relation_repo:t.relation_repo ~niceid_repo:t.niceid_repo
    ~map_err:_map_cascade_err
    ~typeid:cand.typeid ~niceid:cand.niceid ~entity_type:cand.entity_type

(* --- Initialization --- *)

let init root ~config_svc = {
  todo_repo     = Repository.Root.todo root;
  note_repo     = Repository.Root.note root;
  relation_repo = Repository.Root.relation root;
  niceid_repo   = Repository.Root.niceid root;
  graph_svc     = Graph_service.init root;
  config_svc;
}

(* --- Public operations --- *)

let collect t ~max_age_seconds ~now =
  let open Result.Syntax in
  let* candidates = _list_terminal_candidates t ~max_age_seconds ~now in
  let+ filtered = _filter_by_component t candidates in
  List.map (fun c ->
    let age_seconds = now - Data.Timestamp.to_epoch c.updated_at in
    { niceid = c.niceid;
      entity_type = c.entity_type;
      title = c.title;
      age_days = age_seconds / 86400 }
  ) filtered

let run t ~max_age_seconds ~now =
  let open Result.Syntax in
  let* candidates = _list_terminal_candidates t ~max_age_seconds ~now in
  let* filtered = _filter_by_component t candidates in
  let+ rels_counts =
    Data.Result.traverse (fun c -> _delete_candidate t c) filtered
  in
  { items_removed = List.length filtered;
    relations_removed = List.fold_left ( + ) 0 rels_counts }

let collect_with_config t =
  let max_age_seconds = _resolve_max_age t in
  let now = Data.Timestamp.to_epoch (Data.Timestamp.now ()) in
  collect t ~max_age_seconds ~now

let run_with_config t =
  let max_age_seconds = _resolve_max_age t in
  let now = Data.Timestamp.to_epoch (Data.Timestamp.now ()) in
  run t ~max_age_seconds ~now
