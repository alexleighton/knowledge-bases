module Helper = Test_helper

let%expect_test "bs list --count" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "T1"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "T2"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "N1"]);
    let result = Helper.run_bs ~dir ["list"; "--count"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    2 open todos
    1 active note
  |}]

let%expect_test "bs list --count --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "T1"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "N1"]);
    let result = Helper.run_bs ~dir ["list"; "--count"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok"));
  [%expect {|
    [exit 0]
    ok: true
  |}]

let%expect_test "bs list --sort created (default and --asc)" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    Unix.sleepf 1.1;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Second"]);
    let desc = Helper.run_bs ~dir ["list"; "todo"; "--sort"; "created"] in
    Helper.print_result ~dir desc;
    let asc = Helper.run_bs ~dir ["list"; "todo"; "--sort"; "created"; "--asc"] in
    Helper.print_result ~dir asc);
  [%expect {|
    [exit 0]
    kb-1    todo  open          Second
    kb-0    todo  open          First
    [exit 0]
    kb-0    todo  open          First
    kb-1    todo  open          Second
    |}]

let%expect_test "bs list --depends-on filters by relation" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Source"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Target";
            "--depends-on"; "kb-0"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Unrelated"]);
    let result = Helper.run_bs ~dir ["list"; "todo"; "--depends-on"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    kb-0    todo  open          Source
    |}]

let%expect_test "bs list --sort --count fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "--sort"; "created"; "--count"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: --sort cannot be combined with --count
  |}]

let%expect_test "bs list --transitive without filter fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "--transitive"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: --transitive requires exactly one relation filter
  |}]
