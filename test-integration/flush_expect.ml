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
