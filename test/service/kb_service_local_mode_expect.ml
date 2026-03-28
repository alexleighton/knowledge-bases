module Root = Kbases.Repository.Root
module Config = Kbases.Repository.Config
module TodoRepo = Kbases.Repository.Todo
module Service = Kbases.Service.Kb_service
module Lifecycle = Kbases.Service.Lifecycle
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Timestamp = Kbases.Data.Timestamp

let with_git_root = Test_helpers.with_git_root
let with_chdir = Test_helpers.with_chdir
let query_count = Test_helpers.query_count
let pp_error = Test_helpers.pp_item_error
let unwrap_todo_repo = Test_helpers.unwrap_todo_repo

let expect_ok result f =
  match result with
  | Error err -> pp_error err
  | Ok v -> f v

let with_open_kb f =
  expect_ok (Service.open_kb ()) (fun (root, service) ->
    Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f root service))

let%expect_test "open_kb with local mode does not construct sync" =
  with_git_root "kb-open-local-" (fun root ->
    with_chdir root (fun () ->
      ignore (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb")
                ~gc_max_age:None ~mode:(Some "local"));
      with_open_kb (fun _root service ->
        ignore (Service.add_note service
                  ~title:(Title.make "Local note")
                  ~content:(Content.make "Body"));
        Printf.printf "jsonl exists: %b\n"
          (Sys.file_exists (Filename.concat root ".kbases.jsonl"));
        (match Service.flush service with
         | Ok () -> print_endline "flush: ok"
         | Error err -> pp_error err))));
  [%expect {|
    jsonl exists: false
    repository error: Sync is not available in local mode.
  |}]

let%expect_test "open_kb with absent mode key defaults to shared" =
  with_git_root "kb-open-no-mode-" (fun root ->
    with_chdir root (fun () ->
      ignore (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb")
                ~gc_max_age:None ~mode:(Some "shared"));
      (* Remove the mode key to simulate a pre-existing KB *)
      let db_file = Filename.concat root ".kbases.db" in
      (match Root.init ~db_file ~namespace:None with
       | Ok opened ->
           ignore (Config.delete (Root.config opened) "mode");
           Root.close opened
       | Error _ -> ());
      with_open_kb (fun _root service ->
        ignore (Service.add_note service
                  ~title:(Title.make "Shared note")
                  ~content:(Content.make "Body"));
        Printf.printf "jsonl exists: %b\n"
          (Sys.file_exists (Filename.concat root ".kbases.jsonl")))));
  [%expect {|
    jsonl exists: true
  |}]

let%expect_test "force_rebuild with local mode returns error" =
  with_git_root "kb-rebuild-local-" (fun root ->
    with_chdir root (fun () ->
      ignore (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb")
                ~gc_max_age:None ~mode:(Some "local"));
      with_open_kb (fun _root service ->
        match Service.force_rebuild service with
        | Ok () -> print_endline "rebuild: ok"
        | Error err -> pp_error err)));
  [%expect {|
    repository error: Sync is not available in local mode.
  |}]

let%expect_test "open_kb in local mode runs GC without flush" =
  with_git_root "kb-gc-local-" (fun root ->
    with_chdir root (fun () ->
      ignore (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb")
                ~gc_max_age:None ~mode:(Some "local"));
      (* Insert a GC-eligible todo directly: status=Done, old timestamp *)
      let db_file = Filename.concat root ".kbases.db" in
      (match Root.init ~db_file ~namespace:None with
       | Ok opened ->
           let id = Todo.make_id () in
           ignore (unwrap_todo_repo (TodoRepo.import (Root.todo opened)
             ~id ~title:(Title.make "Old done")
             ~content:(Content.make "Body")
             ~status:Todo.Done
             ~created_at:(Timestamp.make 0) ~updated_at:(Timestamp.make 0) ()));
           Root.close opened
       | Error _ -> failwith "failed to open db");
      (* open_kb triggers _run_gc with sync=None *)
      with_open_kb (fun db_root _service ->
        query_count db_root "todo";
        Printf.printf "jsonl exists: %b\n"
          (Sys.file_exists (Filename.concat root ".kbases.jsonl")))));
  [%expect {|
    todo=0
    jsonl exists: false
  |}]
