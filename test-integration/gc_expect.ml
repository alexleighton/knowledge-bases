module Helper = Test_helper

let%expect_test "bs gc removes nothing when no old items" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    let result = Helper.run_bs ~dir ["gc"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    GC: removed 0 item(s), 0 relation(s).
  |}]

let%expect_test "bs gc --dry-run shows nothing when no eligible" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    let result = Helper.run_bs ~dir ["gc"; "--dry-run"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Nothing to collect.
  |}]

let%expect_test "bs gc --set-max-age 14d" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["gc"; "--set-max-age"; "14d"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["gc"; "--show-max-age"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    GC max age set to: 14d
    [exit 0]
    GC max age: 14d
  |}]

let%expect_test "bs gc --show-max-age default" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["gc"; "--show-max-age"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    GC max age: 30d (default)
  |}]

let%expect_test "bs gc --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["gc"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "items_removed: %d\n" (Helper.get_int json "items_removed"));
  [%expect {|
    [exit 0]
    ok: true
    items_removed: 0
  |}]

let%expect_test "bs gc auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["gc"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    GC: removed 0 item(s), 0 relation(s).
  |}]
