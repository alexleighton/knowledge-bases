module Helper = Test_helper

let%expect_test "bs claim open todo" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Fix bug"]);
    let result = Helper.run_bs ~dir ["claim"; "kb-0"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Claimed todo: kb-0  Fix bug
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Title:  Fix bug

    Todo body
  |}]

let%expect_test "bs claim a note fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Research"]);
    let result = Helper.run_bs ~dir ["claim"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: kb-0 is not a todo
  |}]

let%expect_test "bs claim non-open todo fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    ignore (Helper.run_bs ~dir ["update"; "kb-0"; "--status"; "in-progress"]);
    let result = Helper.run_bs ~dir ["claim"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: kb-0 is not open (status: in-progress)
  |}]

let%expect_test "bs claim blocked todo fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocked"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Dependency"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["claim"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: kb-0 is blocked by kb-1
  |}]

let%expect_test "bs claim non-existent niceid" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["claim"; "kb-999"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs claim --json success" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    let result = Helper.run_bs ~dir ["claim"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "action: %s\n" (Helper.get_string json "action");
    Printf.printf "type: %s\n" (Helper.get_string json "type");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: claimed
    type: todo
    niceid: kb-0
  |}]

let%expect_test "bs claim --json error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocked"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Dep"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["claim"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid"));
  [%expect {|
    [exit 1]
    ok: false
    reason: blocked
    niceid: kb-0
  |}]

let%expect_test "bs claim --show" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "My task"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Design doc"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--related-to"; "kb-1"]);
    let result = Helper.run_bs ~dir ["claim"; "kb-0"; "--show"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Claimed todo: kb-0
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Title:  My task

    Todo body

    Outgoing:
      related-to  kb-1  note  Design doc
  |}]

let%expect_test "bs claim auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["claim"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Claimed todo: kb-0  Task
  |}]

let%expect_test "bs claim outside git repo" =
  Helper.with_temp_dir ~name:"kb-claim-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["claim"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]
