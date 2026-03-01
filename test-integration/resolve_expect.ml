module Helper = Test_helper

let%expect_test "bs resolve open todo" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Fix bug"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Resolved todo: kb-0
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: done
    Title:  Fix bug

    Todo body
  |}]

let%expect_test "bs resolve a note fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Research"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: resolve applies only to todos, but kb-0 is a note
  |}]

let%expect_test "bs resolve non-existent niceid" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["resolve"; "kb-999"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs resolve outside git repo" =
  Helper.with_temp_dir ~name:"kb-resolve-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "bs resolve --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "action: %s\n" (Helper.get_string json "action");
    Printf.printf "type: %s\n" (Helper.get_string json "type");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: resolved
    type: todo
    niceid: kb-0
  |}]
