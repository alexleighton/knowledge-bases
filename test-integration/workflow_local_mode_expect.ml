module Helper = Test_helper

let%expect_test "local mode: add and list succeed without creating JSONL file" =
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

let%expect_test "local mode: resolve transitions todo to done" =
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
    let mode_before = Helper.run_bs ~dir ["config"; "get"; "mode"] in
    Helper.print_result ~dir mode_before;
    let set_result = Helper.run_bs ~dir ["config"; "set"; "mode"; "shared"] in
    Helper.print_result ~dir set_result;
    let mode_after = Helper.run_bs ~dir ["config"; "get"; "mode"] in
    Helper.print_result ~dir mode_after;
    let flush_result = Helper.run_bs ~dir ["flush"] in
    Helper.print_result ~dir flush_result;
    Printf.printf "jsonl after: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.jsonl")));
  [%expect {|
    jsonl before: false
    [exit 0]
    local
    [exit 0]
    mode set to: shared
    [exit 0]
    shared
    [exit 0]
    Flushed to .kbases.jsonl
    jsonl after: true
  |}]
