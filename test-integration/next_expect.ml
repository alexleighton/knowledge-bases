module Helper = Test_helper

let%expect_test "bs next claims first open todo" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First task"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Second task"]);
    let result = Helper.run_bs ~dir ["next"] in
    Helper.print_result ~dir result;
    let list = Helper.run_bs ~dir ["list"; "todo"] in
    Helper.print_result ~dir list);
  [%expect {|
    [exit 0]
    Claimed todo: kb-0  First task
    [exit 0]
    kb-1    todo  open          Second task
    kb-0    todo  in-progress   First task
    |}]

let%expect_test "bs next skips blocked and claims unblocked" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocked"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Dependency"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Unblocked"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["next"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Claimed todo: kb-1  Dependency
  |}]

let%expect_test "bs next with no open todos" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    let result = Helper.run_bs ~dir ["next"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    No open unblocked todos
  |}]

let%expect_test "bs next all open blocked" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocked A"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocked B"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "In progress dep"]);
    ignore (Helper.run_bs ~dir ["update"; "kb-2"; "--status"; "in-progress"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-2"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-1"; "--depends-on"; "kb-2"]);
    let result = Helper.run_bs ~dir ["next"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 123]
    STDERR: Error: no available todos (2 open todo(s) blocked)
  |}]

let%expect_test "bs next --json success" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    let result = Helper.run_bs ~dir ["next"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "action: %s\n" (Helper.get_string json "action");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: claimed
    niceid: kb-0
  |}]

let%expect_test "bs next --json empty queue" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["next"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok"));
  [%expect {|
    [exit 0]
    ok: true
  |}]

let%expect_test "bs next --json stuck" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocked"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Dep"]);
    ignore (Helper.run_bs ~dir ["update"; "kb-1"; "--status"; "in-progress"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["next"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason");
    Printf.printf "stuck_count: %d\n"
      (match List.assoc "stuck_count" (match json with `Assoc l -> l | _ -> []) with
       | `Int n -> n | _ -> -1));
  [%expect {|
    [exit 123]
    ok: false
    reason: nothing_available
    stuck_count: 1
  |}]

let%expect_test "bs next --show" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "My task"]);
    let result = Helper.run_bs ~dir ["next"; "--show"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Claimed todo: kb-0
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  My task

    Todo body
    |}]

let%expect_test "bs next auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["next"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Claimed todo: kb-0  Task
  |}]

let%expect_test "bs next outside git repo" =
  Helper.with_temp_dir ~name:"kb-next-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["next"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]
