module Helper = Test_helper

let%expect_test "bs unrelate depends-on" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Source"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Target"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["unrelate"; "kb-0"; "--depends-on"; "kb-1"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Unrelated: kb-0 depends-on kb-1 (removed)
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Source

    Body
    |}]

let%expect_test "bs unrelate bidirectional from either side" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "A"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "B"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--related-to"; "kb-1"]);
    (* unrelate from the other side *)
    let result = Helper.run_bs ~dir ["unrelate"; "kb-1"; "--related-to"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Unrelated: kb-1 related-to kb-0 (removed)
    |}]

let%expect_test "bs unrelate non-existent relation fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "A"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "B"]);
    let result = Helper.run_bs ~dir ["unrelate"; "kb-0"; "--depends-on"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: relation not found
  |}]

let%expect_test "bs unrelate --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Source"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Target"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["unrelate"; "kb-0"; "--depends-on"; "kb-1"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let removed = Helper.get_list json "removed" in
    Printf.printf "removed count: %d\n" (List.length removed);
    let item = List.hd removed in
    Printf.printf "source: %s\n" (Helper.get_string item "source");
    Printf.printf "kind: %s\n" (Helper.get_string item "kind");
    Printf.printf "target: %s\n" (Helper.get_string item "target"));
  [%expect {|
    [exit 0]
    ok: true
    removed count: 1
    source: kb-0
    kind: depends-on
    target: kb-1
  |}]

let%expect_test "bs unrelate auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Source"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Target"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["unrelate"; "kb-0"; "--depends-on"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Unrelated: kb-0 depends-on kb-1 (removed)
  |}]
