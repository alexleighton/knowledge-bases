module Helper = Test_helper
module Sqlite = Kbases.Repository.Sqlite

let%expect_test "local mode: add and list work, no JSONL created" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "local"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My task"]);
    let list_result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list_result;
    Printf.printf "jsonl exists: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.jsonl")));
  [%expect {|
    [exit 0]
    kb-0    todo  open          My task
    jsonl exists: false
  |}]

let%expect_test "local mode: resolve works normally" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "local"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Fix bug"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Resolved todo: kb-0
    |}]

let%expect_test "mode transition: local to shared enables sync" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "local"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My task"]);
    Printf.printf "jsonl before: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.jsonl"));
    (* Change mode from local to shared via direct SQLite update.
       TODO: rework once config updating is supported by the CLI. *)
    let db_path = Filename.concat dir ".kbases.db" in
    let db = Sqlite3.db_open db_path in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () ->
      match Sqlite.exec db "UPDATE config SET value='shared' WHERE key='mode'" with
      | Ok () -> ()
      | Error msg -> failwith ("config update failed: " ^ msg));
    let flush_result = Helper.run_bs ~dir ["flush"] in
    Helper.print_result ~dir flush_result;
    Printf.printf "jsonl after: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.jsonl")));
  [%expect {|
    jsonl before: false
    [exit 0]
    Flushed to .kbases.jsonl
    jsonl after: true
  |}]
