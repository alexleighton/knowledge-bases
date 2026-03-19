module Note = Note_service
module Todo = Todo_service
module Query = Query_service
module Mutation = Mutation_service
module Relation = Relation_service
module Delete = Delete_service

module Gc = Gc_service

type t = {
  notes        : Note.t;
  todos        : Todo.t;
  query        : Query.t;
  mutation     : Mutation.t;
  relation_svc : Relation.t;
  delete_svc   : Delete.t;
  gc_svc       : Gc.t;
  sync         : Sync_service.t option;
  db           : Sqlite3.db;
}

type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

type item = Data.Item.t =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

type agents_md_action = Lifecycle.agents_md_action =
  | Created
  | Appended
  | Already_present

type git_exclude_action = Lifecycle.git_exclude_action =
  | Excluded
  | Already_excluded

type file_action = Lifecycle.file_action =
  | Deleted
  | Not_found

type init_result = Lifecycle.init_result = {
  directory   : string;
  namespace   : string;
  db_file     : string;
  agents_md   : agents_md_action;
  git_exclude : git_exclude_action;
}

type agents_md_uninstall_action = Lifecycle.agents_md_uninstall_action =
  | File_deleted | Section_removed | Section_modified | Not_found

type git_exclude_uninstall_action = Lifecycle.git_exclude_uninstall_action =
  | Entry_removed | Entry_not_found

type uninstall_result = Lifecycle.uninstall_result = {
  directory   : string;
  database    : file_action;
  jsonl       : file_action;
  agents_md   : agents_md_uninstall_action;
  git_exclude : git_exclude_uninstall_action;
}

type relation_entry = Query.relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  blocking    : bool option;
}

type show_result = Query.show_result = {
  item     : item;
  outgoing : relation_entry list;
  incoming : relation_entry list;
}

type relate_spec = Relation.relate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
  blocking      : bool;
}

type relate_result = Relation.relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  target_type   : string;
  target_title  : Data.Title.t;
}

type unrelate_spec = Relation.unrelate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
}

type unrelate_result = Relation.unrelate_result = {
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  kind          : Data.Relation_kind.t;
  bidirectional : bool;
}

type claim_error = Mutation.claim_error =
  | Not_a_todo of string
  | Not_open of { niceid : string; status : string }
  | Blocked of { niceid : string; blocked_by : string list }
  | Nothing_available of { stuck_count : int }
  | Service_error of Item_service.error

type add_with_relations_result = {
  niceid      : Data.Identifier.t;
  typeid      : Data.Uuid.Typeid.t;
  entity_type : string;
  relations   : relation_entry list;
}

type delete_result = Delete.delete_result = {
  niceid            : Data.Identifier.t;
  entity_type       : string;
  relations_removed : int;
}

type delete_error = Delete.delete_error =
  | Blocked_dependency of { niceid : string; dependents : string list }
  | Service_error of Item_service.error

(* --- Error mapping --- *)

let map_lifecycle_error = function
  | Lifecycle.Repository_error msg -> Repository_error msg
  | Lifecycle.Validation_error msg -> Validation_error msg

let map_sync_error_from_item = function
  | Item_service.Repository_error msg -> Repository_error msg
  | Item_service.Validation_error msg -> Validation_error msg

let map_note_error = function
  | Note.Repository_error msg -> Repository_error msg

let map_todo_error = function
  | Todo.Repository_error msg -> Repository_error msg

let map_sync_error = function
  | Sync_service.Sync_failed msg -> Repository_error msg

let _map_sync_to_claim_error e : claim_error = Service_error (map_sync_error e)

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

let relation_entry_of_relate_result (r : Relation.relate_result) : relation_entry = {
  kind        = Data.Relation.kind r.relation;
  niceid      = r.target_niceid;
  entity_type = r.target_type;
  title       = r.target_title;
  blocking    = None;
}

let build_specs = Relation.build_specs
let build_unrelate_specs = Relation.build_unrelate_specs

(* --- Initialization --- *)

let init root = {
  notes    = Note.init root;
  todos    = Todo.init root;
  query    = Query.init root;
  mutation = Mutation.init root;
  relation_svc = Relation.init root;
  delete_svc = Delete.init root;
  gc_svc   = Gc.init root;
  sync     = None;
  db       = Repository.Root.db root;
}

(* --- Lifecycle --- *)

let _run_gc root sync =
  let open Result.Syntax in
  let gc = Gc_service.init root in
  let* result = Gc_service.run_with_config gc
    |> Result.map_error map_sync_error_from_item in
  if result.Gc_service.items_removed > 0 then begin
    let* () = Sync_service.mark_dirty sync |> Result.map_error map_sync_error in
    Sync_service.flush sync |> Result.map_error map_sync_error
  end else Ok ()

let open_kb () =
  let open Result.Syntax in
  let* (root, dir) =
    Lifecycle.open_kb ()
    |> Result.map_error map_lifecycle_error
  in
  let jsonl_path = Filename.concat dir Lifecycle.jsonl_filename in
  let sync = Sync_service.init root ~jsonl_path in
  let* () =
    Sync_service.rebuild_if_needed sync
    |> Result.map_error map_sync_error
  in
  let* () = _run_gc root sync in
  let t = { (init root) with sync = Some sync } in
  Ok (root, t)

let init_kb ~directory ~namespace ~gc_max_age =
  Lifecycle.init_kb ~directory ~namespace ~gc_max_age
  |> Result.map_error map_lifecycle_error

let uninstall_kb ~directory =
  Lifecycle.uninstall_kb ~directory
  |> Result.map_error map_lifecycle_error

(* --- Add operations --- *)

let add_note t ~title ~content =
  _with_flush t (fun () ->
    Note.add t.notes ~title ~content
    |> Result.map_error map_note_error)

let add_todo t ~title ~content ?status () =
  _with_flush t (fun () ->
    Todo.add t.todos ~title ~content ?status ()
    |> Result.map_error map_todo_error)

let add_note_with_relations t ~title ~content ~specs =
  _with_flush t (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () ->
        let open Result.Syntax in
        let* note = Note.add t.notes ~title ~content
                    |> Result.map_error map_note_error in
        let source = Data.Identifier.to_string (Data.Note.niceid note) in
        let* results = Relation.relate_many t.relation_svc ~source ~specs in
        let relations = List.map relation_entry_of_relate_result results in
        Ok { niceid = Data.Note.niceid note;
             typeid = Data.Note.id note;
             entity_type = "note";
             relations }))

let add_todo_with_relations t ~title ~content ~specs ?status () =
  _with_flush t (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () ->
        let open Result.Syntax in
        let* todo = Todo.add t.todos ~title ~content ?status ()
                    |> Result.map_error map_todo_error in
        let source = Data.Identifier.to_string (Data.Todo.niceid todo) in
        let* results = Relation.relate_many t.relation_svc ~source ~specs in
        let relations = List.map relation_entry_of_relate_result results in
        Ok { niceid = Data.Todo.niceid todo;
             typeid = Data.Todo.id todo;
             entity_type = "todo";
             relations }))

(* --- Query operations --- *)

type sort_order = Query.sort_order = Sort_created | Sort_updated
type relation_filter = Query.relation_filter = {
  target    : string;
  kind      : string;
  direction : Graph_service.direction;
}
type list_spec = Query.list_spec = {
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
type list_result = Query.list_result

let build_filters = Query.build_filters

let list t spec =
  Query.list t.query spec

let show t ~identifier =
  Query.show t.query ~identifier

let show_many t ~identifiers =
  Query.show_many t.query ~identifiers

(* --- Mutation operations --- *)

let update t ~identifier ?status ?title ?content () =
  _with_flush t (fun () ->
    Mutation.update t.mutation ~identifier ?status ?title ?content ())

let resolve t ~identifier =
  _with_flush t (fun () ->
    Mutation.resolve t.mutation ~identifier)

let archive t ~identifier =
  _with_flush t (fun () ->
    Mutation.archive t.mutation ~identifier)

let reopen t ~identifier =
  _with_flush t (fun () ->
    Mutation.reopen t.mutation ~identifier)

let next t =
  _with_flush_map t ~map_err:_map_sync_to_claim_error (fun () ->
    Mutation.next t.mutation)

let claim t ~identifier =
  _with_flush_map t ~map_err:_map_sync_to_claim_error (fun () ->
    Mutation.claim t.mutation ~identifier)

let _map_sync_to_delete_error e =
  Delete.Service_error (map_sync_error e)

let delete t ~identifier ~force =
  _with_flush_map t ~map_err:_map_sync_to_delete_error (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Delete.Service_error (Repository_error msg))
      (fun () ->
        Delete.delete t.delete_svc ~identifier ~force))

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

type gc_item = Gc.gc_item = {
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  age_days    : int;
}

type gc_result = Gc.gc_result = {
  items_removed     : int;
  relations_removed : int;
}

type max_age_result = Gc.max_age_result =
  | Configured of string
  | Default

let default_max_age_display = Gc.default_max_age_display

let gc_get_max_age t = Gc.get_max_age t.gc_svc

let gc_set_max_age t age_str = Gc.set_max_age t.gc_svc age_str

let gc_collect_with_config t = Gc.collect_with_config t.gc_svc

let gc_run_with_config t = Gc.run_with_config t.gc_svc

(* --- Sync operations --- *)

let flush t =
  let open Result.Syntax in
  match t.sync with
  | None -> Error (Repository_error "Sync not enabled")
  | Some sync ->
      let* () = Sync_service.mark_dirty sync |> Result.map_error map_sync_error in
      Sync_service.flush sync |> Result.map_error map_sync_error

let force_rebuild t =
  match t.sync with
  | None -> Error (Repository_error "Sync not enabled")
  | Some sync ->
      Sync_service.force_rebuild sync |> Result.map_error map_sync_error
