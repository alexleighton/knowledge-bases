module Lifecycle = Lifecycle
module Query = Query_service
module Show = Show_service
module Mutation = Mutation_service
module Relation = Relation_service
module Delete = Delete_service
module Gc = Gc_service

type t = {
  note_repo    : Repository.Note.t;
  todo_repo    : Repository.Todo.t;
  query_svc    : Query.t;
  show_svc     : Show.t;
  mutation_svc : Mutation.t;
  relation_svc : Relation.t;
  delete_svc   : Delete.t;
  gc_svc       : Gc.t;
  config_svc   : Config_service.t;
  sync         : Sync_service.t option;
  db           : Sqlite3.db;
}

type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

type item = Data.Item.t =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

type add_with_relations_result = {
  niceid      : Data.Identifier.t;
  typeid      : Data.Uuid.Typeid.t;
  entity_type : string;
  relations   : Show.relation_entry list;
}

(* --- Error mapping --- *)

let map_lifecycle_error = function
  | Lifecycle.Repository_error msg -> Repository_error msg
  | Lifecycle.Validation_error msg -> Validation_error msg

let map_sync_error = function
  | Sync_service.Sync_failed msg -> Repository_error msg

let _map_sync_to_claim_error e : Mutation.claim_error =
  Mutation.Service_error (map_sync_error e)

let _map_sync_to_delete_error e =
  Delete.Service_error (map_sync_error e)

(* --- Internal helpers --- *)

let _with_flush_map t ~map_err f =
  let open Result.Syntax in
  let* () = match t.sync with
    | None -> Ok ()
    | Some sync -> Sync_service.mark_dirty sync |> Result.map_error map_err
  in
  let* result = f () in
  let* () = match t.sync with
    | None -> Ok ()
    | Some sync -> Sync_service.flush sync |> Result.map_error map_err
  in
  Ok result

let _with_flush t f =
  _with_flush_map t ~map_err:map_sync_error f

let _relation_entry_of_relate_result (r : Relation.relate_result) : Show.relation_entry =
  let open Relation in
  { Show.kind = Data.Relation.kind r.relation;
    niceid      = r.target_niceid;
    entity_type = r.target_type;
    title       = r.target_title;
    blocking    = None; }

let build_specs = Relation.build_specs
let build_unrelate_specs = Relation.build_unrelate_specs
let build_filters = Query.build_filters

(* --- Initialization --- *)

let init root ~config_svc = {
  note_repo = Repository.Root.note root;
  todo_repo = Repository.Root.todo root;
  query_svc    = Query.init root;
  show_svc     = Show.init root;
  mutation_svc = Mutation.init root;
  relation_svc = Relation.init root;
  delete_svc = Delete.init root;
  gc_svc   = Gc.init root ~config_svc;
  config_svc;
  sync     = None;
  db       = Repository.Root.db root;
}

let config_svc t = t.config_svc

(* --- Lifecycle --- *)

let _run_gc root ~config_svc sync =
  let open Result.Syntax in
  let gc = Gc_service.init root ~config_svc in
  let* result = Gc_service.run_with_config gc in
  if result.Gc_service.items_removed > 0 then
    match sync with
    | None -> Ok ()
    | Some s ->
        let* () = Sync_service.mark_dirty s |> Result.map_error map_sync_error in
        Sync_service.flush s |> Result.map_error map_sync_error
  else Ok ()

let open_kb () =
  let open Result.Syntax in
  let* (root, dir) =
    Lifecycle.open_kb ()
    |> Result.map_error map_lifecycle_error
  in
  let config_svc = Config_service.init root ~dir in
  let mode = match Config_service.get config_svc "mode" with
    | Ok { Config_service.value; _ } -> value
    | Error _ -> "shared"
  in
  if mode = "local" then begin
    let* () = _run_gc root ~config_svc None in
    let t = init root ~config_svc in
    Ok (root, t)
  end else begin
    let jsonl_path = Filename.concat dir Data.Kb_filenames.jsonl in
    let sync = Sync_service.init root ~jsonl_path in
    let* () =
      Sync_service.rebuild_if_needed sync
      |> Result.map_error map_sync_error
    in
    let* () = _run_gc root ~config_svc (Some sync) in
    let t = { (init root ~config_svc) with sync = Some sync } in
    Ok (root, t)
  end

let init_kb ~directory ~namespace ~gc_max_age ~mode =
  Lifecycle.init_kb ~directory ~namespace ~gc_max_age ~mode
  |> Result.map_error map_lifecycle_error

let uninstall_kb ~directory =
  Lifecycle.uninstall_kb ~directory
  |> Result.map_error map_lifecycle_error

(* --- Add operations --- *)

let add_note t ~title ~content =
  _with_flush t (fun () ->
    Repository.Note.create t.note_repo ~title ~content ()
    |> Result.map_error Item_service.map_note_repo_error)

let add_todo t ~title ~content ?status () =
  _with_flush t (fun () ->
    Repository.Todo.create t.todo_repo ~title ~content ?status ()
    |> Result.map_error Item_service.map_todo_repo_error)

let _add_with_relations (type a) t ~create ~niceid ~id ~entity_type ~specs =
  _with_flush t (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () ->
        let open Result.Syntax in
        let* (entity : a) = create () in
        let source = Data.Identifier.to_string (niceid entity) in
        let* results = Relation.relate_many t.relation_svc ~source ~specs in
        let relations = List.map _relation_entry_of_relate_result results in
        Ok { niceid = niceid entity; typeid = id entity;
             entity_type; relations }))

let add_note_with_relations t ~title ~content ~specs =
  _add_with_relations t ~specs ~entity_type:"note"
    ~niceid:Data.Note.niceid ~id:Data.Note.id
    ~create:(fun () ->
      Repository.Note.create t.note_repo ~title ~content ()
      |> Result.map_error Item_service.map_note_repo_error)

let add_todo_with_relations t ~title ~content ~specs ?status () =
  _add_with_relations t ~specs ~entity_type:"todo"
    ~niceid:Data.Todo.niceid ~id:Data.Todo.id
    ~create:(fun () ->
      Repository.Todo.create t.todo_repo ~title ~content ?status ()
      |> Result.map_error Item_service.map_todo_repo_error)

(* --- Query operations --- *)

let list t spec =
  Query.list t.query_svc spec

let show t ~identifier =
  Show.show t.show_svc ~identifier

let show_many t ~identifiers =
  Show.show_many t.show_svc ~identifiers

(* --- Mutation operations --- *)

let update t ~identifier ?status ?title ?content () =
  _with_flush t (fun () ->
    Mutation.update t.mutation_svc ~identifier ?status ?title ?content ())

let resolve_many t ~identifiers =
  _with_flush t (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () -> Mutation.resolve_many t.mutation_svc ~identifiers))

let archive_many t ~identifiers =
  _with_flush t (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () -> Mutation.archive_many t.mutation_svc ~identifiers))

let reopen_many t ~identifiers =
  _with_flush t (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () -> Mutation.reopen_many t.mutation_svc ~identifiers))

let next t =
  _with_flush_map t ~map_err:_map_sync_to_claim_error (fun () ->
    Mutation.next t.mutation_svc)

let claim t ~identifier =
  _with_flush_map t ~map_err:_map_sync_to_claim_error (fun () ->
    Mutation.claim t.mutation_svc ~identifier)

let delete_many t ~identifiers ~force =
  _with_flush_map t ~map_err:_map_sync_to_delete_error (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Delete.Service_error (Repository_error msg))
      (fun () ->
        Delete.delete_many t.delete_svc ~identifiers ~force))

let relate t ~source ~specs =
  _with_flush t (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () ->
        Relation.relate_many t.relation_svc ~source ~specs))

let unrelate t ~source ~specs =
  _with_flush t (fun () ->
    Relation.unrelate_many t.relation_svc ~source ~specs)

(* --- GC operations --- *)

let gc_collect_with_config t = Gc.collect_with_config t.gc_svc

let gc_run_with_config t = Gc.run_with_config t.gc_svc

(* --- Sync operations --- *)

let flush t =
  let open Result.Syntax in
  match t.sync with
  | None -> Error (Repository_error "Sync is not available in local mode.")
  | Some sync ->
      let* () = Sync_service.mark_dirty sync |> Result.map_error map_sync_error in
      Sync_service.flush sync |> Result.map_error map_sync_error

let force_rebuild t =
  match t.sync with
  | None -> Error (Repository_error "Sync is not available in local mode.")
  | Some sync ->
      Sync_service.force_rebuild sync |> Result.map_error map_sync_error
