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

let%expect_test "auto-GC on open_kb collects eligible Done todo" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir
      ["init"; "-d"; dir; "-n"; "kb"; "--gc-max-age"; "0"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    let result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
  |}]

let%expect_test "auto-GC on open_kb skips non-terminal Open todo" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir
      ["init"; "-d"; dir; "-n"; "kb"; "--gc-max-age"; "0"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    let result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    kb-0    todo  open          Task
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
