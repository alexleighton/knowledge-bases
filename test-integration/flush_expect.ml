module Helper = Test_helper

let%expect_test "bs flush after adding entities" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Test note"]);
    let result = Helper.run_bs ~dir ["flush"] in
    Helper.print_result ~dir result;
    Printf.printf "jsonl exists=%b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.jsonl")));
  [%expect {|
    [exit 0]
    Flushed to .kbases.jsonl
    jsonl exists=true
    |}]

let%expect_test "bs flush on empty KB" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["flush"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Flushed to .kbases.jsonl
    |}]

let%expect_test "bs flush outside git repo" =
  Helper.with_temp_dir ~name:"kb-flush-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["flush"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
    |}]

let%expect_test "add command auto-flushes to JSONL" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "My todo"]);
    Printf.printf "jsonl exists=%b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.jsonl")));
  [%expect {|
    jsonl exists=true
    |}]

let%expect_test "bs flush --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Item"]);
    let result = Helper.run_bs ~dir ["flush"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "action: %s\n" (Helper.get_string json "action");
    Printf.printf "file: %s\n" (Helper.get_string json "file"));
  [%expect {|
    [exit 0]
    ok: true
    action: flushed
    file: .kbases.jsonl
  |}]

let%expect_test "bs flush in local mode returns error" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "local"]);
    let result = Helper.run_bs ~dir ["flush"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Sync is not available in local mode.
  |}]

let%expect_test "bs flush --json in local mode returns json error" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "local"]);
    let result = Helper.run_bs ~dir ["flush"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    if result.stderr = "" then print_endline "stderr empty: true"
    else Printf.printf "unexpected stderr: %s\n" result.stderr;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason"));
  [%expect {|
    [exit 1]
    stderr empty: true
    ok: false
    reason: error
  |}]

let%expect_test "bs flush auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["flush"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Flushed to .kbases.jsonl
  |}]
