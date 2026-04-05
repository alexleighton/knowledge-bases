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
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Fix bug

    Todo body
    |}]

let%expect_test "bs resolve already-done todo fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Fix bug"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: nothing to update
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
    let resolved = Helper.get_list json "resolved" in
    Printf.printf "count: %d\n" (List.length resolved);
    let item = List.hd resolved in
    Printf.printf "type: %s\n" (Helper.get_string item "type");
    Printf.printf "niceid: %s\n" (Helper.get_string item "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    count: 1
    type: todo
    niceid: kb-0
  |}]

let%expect_test "bs resolve --json error not found" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["resolve"; "kb-999"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    if result.stderr = "" then print_endline "stderr empty: true"
    else Printf.printf "unexpected stderr: %s\n" result.stderr;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason");
    Printf.printf "message: %s\n" (Helper.get_string json "message"));
  [%expect {|
    [exit 1]
    stderr empty: true
    ok: false
    reason: error
    message: item not found: kb-999
  |}]

let%expect_test "bs resolve --json error on note" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Research"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"; "--json"] in
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

let%expect_test "bs resolve auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Resolved todo: kb-0
  |}]

(* -- Multi-ID tests -- *)

let%expect_test "bs resolve multiple todos" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"A" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"B" ["add"; "todo"; "Second"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"; "kb-1"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"; "kb-1"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Resolved todo: kb-0
    Resolved todo: kb-1
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: done
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  First

    A
    ---
    todo kb-1 (<TYPEID>)
    Status: done
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Second

    B
    |}]

let%expect_test "bs resolve multiple --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"A" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"B" ["add"; "todo"; "Second"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"; "kb-1"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let resolved = Helper.get_list json "resolved" in
    Printf.printf "count: %d\n" (List.length resolved);
    List.iter (fun item ->
      Printf.printf "%s %s\n"
        (Helper.get_string item "type")
        (Helper.get_string item "niceid")) resolved);
  [%expect {|
    [exit 0]
    ok: true
    count: 2
    todo kb-0
    todo kb-1
  |}]

let%expect_test "bs resolve multi-ID atomic failure" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"A" ["add"; "todo"; "Good"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"; "kb-999"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Good

    A
    |}]
