module Root = Kbases.Repository.Root
module TodoRepo = Kbases.Repository.Todo
module NoteRepo = Kbases.Repository.Note
module RelationRepo = Kbases.Repository.Relation
module Config = Kbases.Repository.Config
module Sync = Kbases.Service.Sync_service
module Jsonl = Kbases.Repository.Jsonl
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid

let _unwrap_sync = function
  | Ok v -> v
  | Error (Sync.Sync_failed msg) -> failwith ("sync failed: " ^ msg)

let _unwrap_todo = function
  | Ok v -> v
  | Error _ -> failwith "todo error"

let _unwrap_note = function
  | Ok v -> v
  | Error _ -> failwith "note error"

let _with_sync f =
  let tmp_dir = Filename.temp_dir "sync_test" "" in
  let db_file = Filename.concat tmp_dir "test.db" in
  let jsonl_path = Filename.concat tmp_dir "test.jsonl" in
  match Root.init ~db_file ~namespace:(Some "kb") with
  | Error (Root.Backend_failure msg) -> failwith ("root init: " ^ msg)
  | Ok root ->
      Fun.protect
        ~finally:(fun () ->
          Root.close root;
          (try Sys.remove db_file with Sys_error _ -> ());
          (try Sys.remove jsonl_path with Sys_error _ -> ());
          (try Unix.rmdir tmp_dir with Unix.Unix_error _ -> ()))
        (fun () ->
          ignore (Config.set (Root.config root) "namespace" "kb");
          let sync = Sync.init root ~jsonl_path in
          f root sync jsonl_path)

let%expect_test "flush writes JSONL file after mark_dirty" =
  _with_sync (fun root sync jsonl_path ->
    ignore (_unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Test todo") ~content:(Content.make "Body") ()));
    ignore (_unwrap_note (NoteRepo.create (Root.note root)
      ~title:(Title.make "Test note") ~content:(Content.make "Note body") ()));

    _unwrap_sync (Sync.mark_dirty sync);
    _unwrap_sync (Sync.flush sync);

    Printf.printf "jsonl exists=%b\n" (Sys.file_exists jsonl_path);
    let (header, records) =
      match Jsonl.read ~path:jsonl_path with
      | Ok v -> v
      | Error _ -> failwith "read failed"
    in
    Printf.printf "entity_count=%d record_count=%d namespace=%s\n"
      header.entity_count (List.length records) header.namespace);
  [%expect {|
    jsonl exists=true
    entity_count=2 record_count=2 namespace=kb
    |}]

let%expect_test "flush without mark_dirty does nothing" =
  _with_sync (fun root sync jsonl_path ->
    ignore (_unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Test") ~content:(Content.make "Body") ()));

    _unwrap_sync (Sync.flush sync);
    Printf.printf "jsonl exists=%b\n" (Sys.file_exists jsonl_path));
  [%expect {|
    jsonl exists=false
    |}]

let%expect_test "flush updates content hash in config" =
  _with_sync (fun root sync _jsonl_path ->
    ignore (_unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "Body") ()));
    _unwrap_sync (Sync.mark_dirty sync);
    _unwrap_sync (Sync.flush sync);

    let hash1 = match Config.get (Root.config root) "content_hash" with
      | Ok h -> h | Error _ -> failwith "no hash" in

    ignore (_unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "Body") ()));
    _unwrap_sync (Sync.mark_dirty sync);
    _unwrap_sync (Sync.flush sync);

    let hash2 = match Config.get (Root.config root) "content_hash" with
      | Ok h -> h | Error _ -> failwith "no hash" in

    Printf.printf "hashes differ=%b\n" (not (String.equal hash1 hash2)));
  [%expect {|
    hashes differ=true
    |}]

let%expect_test "force_rebuild replaces DB content from JSONL" =
  _with_sync (fun root sync jsonl_path ->
    let tid = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs" in
    let nid = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
    let niceid = Identifier.make "kb" 0 in
    let todo = Todo.make tid niceid (Title.make "From file") (Content.make "Body") Todo.Open in
    let note = Note.make nid niceid (Title.make "A note") (Content.make "Note body") Note.Active in
    let rel = Relation.make ~source:tid ~target:nid
      ~kind:(Relation_kind.make "blocks") ~bidirectional:false in

    ignore (match Jsonl.write ~path:jsonl_path ~namespace:"kb"
      ~todos:[todo] ~notes:[note] ~relations:[rel] with
      | Ok h -> h | Error _ -> failwith "write failed");

    _unwrap_sync (Sync.force_rebuild sync);

    let todos = _unwrap_todo (TodoRepo.list_all (Root.todo root)) in
    let notes = _unwrap_note (NoteRepo.list_all (Root.note root)) in
    let rels = match RelationRepo.list_all (Root.relation root) with
      | Ok r -> r | Error _ -> failwith "list_all failed" in
    Printf.printf "todos=%d notes=%d relations=%d\n"
      (List.length todos) (List.length notes) (List.length rels);

    let t = List.hd todos in
    Printf.printf "todo id=%s title=%s niceid=%s\n"
      (Typeid.to_string (Todo.id t))
      (Title.to_string (Todo.title t))
      (Identifier.to_string (Todo.niceid t)));
  [%expect {|
    todos=1 notes=1 relations=1
    todo id=todo_0123456789abcdefghjkmnpqrs title=From file niceid=kb-1
    |}]

let%expect_test "rebuild_if_needed detects hash mismatch" =
  _with_sync (fun root sync jsonl_path ->
    ignore (_unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Original") ~content:(Content.make "Body") ()));
    _unwrap_sync (Sync.mark_dirty sync);
    _unwrap_sync (Sync.flush sync);

    let tid = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs" in
    let niceid = Identifier.make "kb" 0 in
    let new_todo = Todo.make tid niceid (Title.make "External") (Content.make "Body") Todo.Open in
    ignore (match Jsonl.write ~path:jsonl_path ~namespace:"kb"
      ~todos:[new_todo] ~notes:[] ~relations:[] with
      | Ok h -> h | Error _ -> failwith "write failed");

    _unwrap_sync (Sync.rebuild_if_needed sync);

    let todos = _unwrap_todo (TodoRepo.list_all (Root.todo root)) in
    Printf.printf "todo count=%d\n" (List.length todos);
    let t = List.hd todos in
    Printf.printf "title=%s\n" (Title.to_string (Todo.title t)));
  [%expect {|
    todo count=1
    title=External
    |}]

let%expect_test "rebuild_if_needed no-ops when hashes match" =
  _with_sync (fun root sync _jsonl_path ->
    ignore (_unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Original") ~content:(Content.make "Body") ()));
    _unwrap_sync (Sync.mark_dirty sync);
    _unwrap_sync (Sync.flush sync);

    _unwrap_sync (Sync.rebuild_if_needed sync);

    let todos = _unwrap_todo (TodoRepo.list_all (Root.todo root)) in
    Printf.printf "todo count=%d title=%s\n"
      (List.length todos)
      (Title.to_string (Todo.title (List.hd todos))));
  [%expect {|
    todo count=1 title=Original
    |}]

let%expect_test "rebuild_if_needed no-ops when no JSONL file" =
  _with_sync (fun _root sync _jsonl_path ->
    _unwrap_sync (Sync.rebuild_if_needed sync);
    print_endline "ok");
  [%expect {|
    ok
    |}]
