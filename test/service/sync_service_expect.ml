module Root = Kbases.Repository.Root
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
module Timestamp = Kbases.Data.Timestamp

let unwrap_sync = function
  | Ok v -> v
  | Error (Sync.Sync_failed msg) -> failwith ("sync failed: " ^ msg)

open Test_helpers

let unwrap_todo = unwrap_todo_repo
let unwrap_note = unwrap_note_repo

let with_sync f =
  with_temp_dir "sync_test" (fun tmp_dir ->
    let db_file = Filename.concat tmp_dir "test.db" in
    let jsonl_path = Filename.concat tmp_dir "test.jsonl" in
    match Root.init ~db_file ~namespace:(Some "kb") with
    | Error (Root.Backend_failure msg) -> failwith ("root init: " ^ msg)
    | Ok root ->
        Fun.protect
          ~finally:(fun () -> Root.close root)
          (fun () ->
            ignore (Config.set (Root.config root) "namespace" "kb");
            let sync = Sync.init root ~jsonl_path in
            f root sync jsonl_path))

let%expect_test "flush writes JSONL file after mark_dirty" =
  with_sync (fun root sync jsonl_path ->
    ignore (unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Test todo") ~content:(Content.make "Body") ()));
    ignore (unwrap_note (NoteRepo.create (Root.note root)
      ~title:(Title.make "Test note") ~content:(Content.make "Note body") ()));

    unwrap_sync (Sync.mark_dirty sync);
    unwrap_sync (Sync.flush sync);

    Printf.printf "jsonl exists=%b\n" (Sys.file_exists jsonl_path);
    let (header, records) =
      match Jsonl.read ~path:jsonl_path with
      | Ok v -> v
      | Error _ -> failwith "read failed"
    in
    Printf.printf "record_count=%d namespace=%s\n"
      (List.length records) header.namespace);
  [%expect {|
    jsonl exists=true
    record_count=2 namespace=kb
    |}]

let%expect_test "flush without mark_dirty does nothing" =
  with_sync (fun root sync jsonl_path ->
    ignore (unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Test") ~content:(Content.make "Body") ()));

    unwrap_sync (Sync.flush sync);
    Printf.printf "jsonl exists=%b\n" (Sys.file_exists jsonl_path));
  [%expect {|
    jsonl exists=false
    |}]

let%expect_test "flush updates content hash in config" =
  with_sync (fun root sync _jsonl_path ->
    ignore (unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "Body") ()));
    unwrap_sync (Sync.mark_dirty sync);
    unwrap_sync (Sync.flush sync);

    let hash1 = match Config.get (Root.config root) "content_hash" with
      | Ok h -> h | Error _ -> failwith "no hash" in

    ignore (unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "Body") ()));
    unwrap_sync (Sync.mark_dirty sync);
    unwrap_sync (Sync.flush sync);

    let hash2 = match Config.get (Root.config root) "content_hash" with
      | Ok h -> h | Error _ -> failwith "no hash" in

    Printf.printf "hashes differ=%b\n" (not (String.equal hash1 hash2)));
  [%expect {|
    hashes differ=true
    |}]

let%expect_test "force_rebuild replaces DB content from JSONL" =
  with_sync (fun root sync jsonl_path ->
    let tid = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs" in
    let nid = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
    let niceid = Identifier.make "kb" 0 in
    let todo = Todo.make tid niceid (Title.make "From file") (Content.make "Body") Todo.Open ~created_at:(Timestamp.make 1710000000) ~updated_at:(Timestamp.make 1710000000) in
    let note = Note.make nid niceid (Title.make "A note") (Content.make "Note body") Note.Active ~created_at:(Timestamp.make 1710000000) ~updated_at:(Timestamp.make 1710000000) in
    let rel = Relation.make ~source:tid ~target:nid
      ~kind:(Relation_kind.make "blocks") ~bidirectional:false ~blocking:false in

    (match Jsonl.write ~path:jsonl_path ~namespace:"kb"
      ~todos:[todo] ~notes:[note] ~relations:[rel] with
      | Ok () -> () | Error _ -> failwith "write failed");

    unwrap_sync (Sync.force_rebuild sync);

    let todos = unwrap_todo (TodoRepo.list_all (Root.todo root)) in
    let notes = unwrap_note (NoteRepo.list_all (Root.note root)) in
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
  with_sync (fun root sync jsonl_path ->
    ignore (unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Original") ~content:(Content.make "Body") ()));
    unwrap_sync (Sync.mark_dirty sync);
    unwrap_sync (Sync.flush sync);

    let tid = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs" in
    let niceid = Identifier.make "kb" 0 in
    let new_todo = Todo.make tid niceid (Title.make "External") (Content.make "Body") Todo.Open ~created_at:(Timestamp.make 1710000000) ~updated_at:(Timestamp.make 1710000000) in
    (match Jsonl.write ~path:jsonl_path ~namespace:"kb"
      ~todos:[new_todo] ~notes:[] ~relations:[] with
      | Ok () -> () | Error _ -> failwith "write failed");

    unwrap_sync (Sync.rebuild_if_needed sync);

    let todos = unwrap_todo (TodoRepo.list_all (Root.todo root)) in
    Printf.printf "todo count=%d\n" (List.length todos);
    let t = List.hd todos in
    Printf.printf "title=%s\n" (Title.to_string (Todo.title t)));
  [%expect {|
    todo count=1
    title=External
    |}]

let%expect_test "rebuild_if_needed no-ops when hashes match" =
  with_sync (fun root sync _jsonl_path ->
    ignore (unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Original") ~content:(Content.make "Body") ()));
    unwrap_sync (Sync.mark_dirty sync);
    unwrap_sync (Sync.flush sync);

    unwrap_sync (Sync.rebuild_if_needed sync);

    let todos = unwrap_todo (TodoRepo.list_all (Root.todo root)) in
    Printf.printf "todo count=%d title=%s\n"
      (List.length todos)
      (Title.to_string (Todo.title (List.hd todos))));
  [%expect {|
    todo count=1 title=Original
    |}]

let%expect_test "rebuild_if_needed no-ops when no JSONL file" =
  with_sync (fun _root sync _jsonl_path ->
    unwrap_sync (Sync.rebuild_if_needed sync);
    print_endline "ok");
  [%expect {|
    ok
    |}]
