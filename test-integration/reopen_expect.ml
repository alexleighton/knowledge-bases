module Helper = Test_helper

let%expect_test "bs reopen resolved todo" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Fix bug"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    let result = Helper.run_bs ~dir ["reopen"; "kb-0"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Reopened todo: kb-0
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Fix bug

    Todo body
    |}]

let%expect_test "bs reopen archived note" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Research"]);
    ignore (Helper.run_bs ~dir ["archive"; "kb-0"]);
    let result = Helper.run_bs ~dir ["reopen"; "kb-0"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Reactivated note: kb-0
    [exit 0]
    note kb-0 (<TYPEID>)
    Status: active
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Research

    Note body
    |}]

let%expect_test "bs reopen open todo fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    let result = Helper.run_bs ~dir ["reopen"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: kb-0 is not in a terminal state (status: open)
  |}]

let%expect_test "bs reopen non-existent item" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["reopen"; "kb-999"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs reopen --json todo" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    let result = Helper.run_bs ~dir ["reopen"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "action: %s\n" (Helper.get_string json "action");
    Printf.printf "type: %s\n" (Helper.get_string json "type");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: reopened
    type: todo
    niceid: kb-0
  |}]

let%expect_test "bs reopen --json note" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Research"]);
    ignore (Helper.run_bs ~dir ["archive"; "kb-0"]);
    let result = Helper.run_bs ~dir ["reopen"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "action: %s\n" (Helper.get_string json "action");
    Printf.printf "type: %s\n" (Helper.get_string json "type");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: reactivated
    type: note
    niceid: kb-0
  |}]

let%expect_test "bs reopen auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["reopen"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Reopened todo: kb-0
  |}]
