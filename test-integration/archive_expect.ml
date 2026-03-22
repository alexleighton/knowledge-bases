module Helper = Test_helper

let%expect_test "bs archive active note" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Research"]);
    let result = Helper.run_bs ~dir ["archive"; "kb-0"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Archived note: kb-0
    [exit 0]
    note kb-0 (<TYPEID>)
    Status: archived
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Research

    Note body
    |}]

let%expect_test "bs archive already-archived note fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Research"]);
    ignore (Helper.run_bs ~dir ["archive"; "kb-0"]);
    let result = Helper.run_bs ~dir ["archive"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: nothing to update
  |}]

let%expect_test "bs archive a todo fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Fix bug"]);
    let result = Helper.run_bs ~dir ["archive"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: archive applies only to notes, but kb-0 is a todo
  |}]

let%expect_test "bs archive non-existent niceid" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["archive"; "kb-999"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs archive outside git repo" =
  Helper.with_temp_dir ~name:"kb-archive-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["archive"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "bs archive --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "My note"]);
    let result = Helper.run_bs ~dir ["archive"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let archived = Helper.get_list json "archived" in
    Printf.printf "count: %d\n" (List.length archived);
    let item = List.hd archived in
    Printf.printf "type: %s\n" (Helper.get_string item "type");
    Printf.printf "niceid: %s\n" (Helper.get_string item "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    count: 1
    type: note
    niceid: kb-0
  |}]

let%expect_test "bs archive --json error not found" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["archive"; "kb-999"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    Printf.printf "stderr empty: %b\n" (result.stderr = "");
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

let%expect_test "bs archive --json error on todo" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Fix bug"]);
    let result = Helper.run_bs ~dir ["archive"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    Printf.printf "stderr empty: %b\n" (result.stderr = "");
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason"));
  [%expect {|
    [exit 1]
    stderr empty: true
    ok: false
    reason: error
  |}]

let%expect_test "bs archive auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "My note"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["archive"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Archived note: kb-0
  |}]

(* -- Multi-ID tests -- *)

let%expect_test "bs archive multiple notes" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"A" ["add"; "note"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"B" ["add"; "note"; "Second"]);
    let result = Helper.run_bs ~dir ["archive"; "kb-0"; "kb-1"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"; "kb-1"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Archived note: kb-0
    Archived note: kb-1
    [exit 0]
    note kb-0 (<TYPEID>)
    Status: archived
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  First

    A
    ---
    note kb-1 (<TYPEID>)
    Status: archived
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Second

    B
    |}]

let%expect_test "bs archive multiple --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"A" ["add"; "note"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"B" ["add"; "note"; "Second"]);
    let result = Helper.run_bs ~dir ["archive"; "kb-0"; "kb-1"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let archived = Helper.get_list json "archived" in
    Printf.printf "count: %d\n" (List.length archived);
    List.iter (fun item ->
      Printf.printf "%s %s\n"
        (Helper.get_string item "type")
        (Helper.get_string item "niceid")) archived);
  [%expect {|
    [exit 0]
    ok: true
    count: 2
    note kb-0
    note kb-1
  |}]

let%expect_test "bs archive multi-ID atomic failure" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"A" ["add"; "note"; "Good"]);
    let result = Helper.run_bs ~dir ["archive"; "kb-0"; "kb-999"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
    [exit 0]
    note kb-0 (<TYPEID>)
    Status: active
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Good

    A
    |}]
