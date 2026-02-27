module Note = Note_service
module Todo = Todo_service
module Query = Query_service
module Mutation = Mutation_service
module Relation = Relation_service

type t = {
  notes        : Note.t;
  todos        : Todo.t;
  query        : Query.t;
  mutation     : Mutation.t;
  relation_svc : Relation.t;
  sync         : Sync_service.t option;
}

type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

type item = Item_service.item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

type init_result = Lifecycle.init_result = {
  directory : string;
  namespace : string;
  db_file   : string;
}

type relation_entry = Query.relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
}

type show_result = Query.show_result = {
  item     : item;
  outgoing : relation_entry list;
  incoming : relation_entry list;
}

type relate_result = Relation.relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
}

let init root = {
  notes    = Note.init root;
  todos    = Todo.init root;
  query    = Query.init root;
  mutation = Mutation.init root;
  relation_svc = Relation.init root;
  sync     = None;
}

let map_lifecycle_error = function
  | Lifecycle.Repository_error msg -> Repository_error msg
  | Lifecycle.Validation_error msg -> Validation_error msg

let map_note_error = function
  | Note.Repository_error msg -> Repository_error msg

let map_todo_error = function
  | Todo.Repository_error msg -> Repository_error msg

let map_sync_error = function
  | Sync_service.Sync_failed msg -> Repository_error msg

let _with_flush t f =
  let open Result.Syntax in
  let* () = match t.sync with
    | None -> Ok ()
    | Some sync -> Sync_service.mark_dirty sync |> Result.map_error map_sync_error
  in
  let* result = f () in
  let* () = match t.sync with
    | None -> Ok ()
    | Some sync -> Sync_service.flush sync |> Result.map_error map_sync_error
  in
  Ok result

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
  let t = { (init root) with sync = Some sync } in
  Ok (root, t)

let init_kb ~directory ~namespace =
  Lifecycle.init_kb ~directory ~namespace
  |> Result.map_error map_lifecycle_error

let add_note t ~title ~content =
  _with_flush t (fun () ->
    Note.add t.notes ~title ~content
    |> Result.map_error map_note_error)

let add_todo t ~title ~content ?status () =
  _with_flush t (fun () ->
    Todo.add t.todos ~title ~content ?status ()
    |> Result.map_error map_todo_error)

let list t ~entity_type ~statuses =
  Query.list t.query ~entity_type ~statuses

let show t ~identifier =
  Query.show t.query ~identifier

let update t ~identifier ?status ?title ?content () =
  _with_flush t (fun () ->
    Mutation.update t.mutation ~identifier ?status ?title ?content ())

let resolve t ~identifier =
  _with_flush t (fun () ->
    Mutation.resolve t.mutation ~identifier)

let archive t ~identifier =
  _with_flush t (fun () ->
    Mutation.archive t.mutation ~identifier)

let relate t ~source ~target ~kind ~bidirectional =
  _with_flush t (fun () ->
    Relation.relate t.relation_svc ~source ~target ~kind ~bidirectional)

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
