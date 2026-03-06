module Helper = Test_helper

let%expect_test "bs update todo status" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Todo title"]);
    let result = Helper.run_bs ~dir ["update"; "kb-0"; "--status"; "in-progress"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Updated todo: kb-0
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Title:  Todo title

    Todo body
  |}]

let%expect_test "bs update note title" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Old title"]);
    let result = Helper.run_bs ~dir ["update"; "kb-0"; "--title"; "New title"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Updated note: kb-0
    [exit 0]
    note kb-0 (<TYPEID>)
    Status: active
    Title:  New title

    Note body
  |}]

let%expect_test "bs update content auto-stdin" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Old body" ["add"; "todo"; "Title"]);
    let result = Helper.run_bs ~dir ~stdin:"New body" ["update"; "kb-0"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Updated todo: kb-0
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Title:  Title

    New body
  |}]

let%expect_test "bs update content with --content flag" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Old body" ["add"; "todo"; "Title"]);
    let result = Helper.run_bs ~dir
      ["update"; "kb-0"; "--content"; "New body from flag"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Updated todo: kb-0
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Title:  Title

    New body from flag
  |}]

let%expect_test "bs update multiple fields at once" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Old body" ["add"; "todo"; "Old title"]);
    let result = Helper.run_bs ~dir ~stdin:"New body"
      ["update"; "kb-0"; "--status"; "in-progress"; "--title"; "New title"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Updated todo: kb-0
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Title:  New title

    New body
  |}]

let%expect_test "bs update with no flags" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Title"]);
    let result = Helper.run_bs ~dir ["update"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: nothing to update
  |}]

let%expect_test "bs update with invalid status for entity type" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Title"]);
    let result = Helper.run_bs ~dir ["update"; "kb-0"; "--status"; "done"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: invalid status "done" for note
  |}]

let%expect_test "bs update non-existent niceid" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["update"; "kb-999"; "--status"; "done"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs update outside git repo" =
  Helper.with_temp_dir ~name:"kb-update-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["update"; "kb-0"; "--status"; "done"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "bs update --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    let result = Helper.run_bs ~dir ["update"; "kb-0"; "--status"; "in-progress"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "action: %s\n" (Helper.get_string json "action");
    Printf.printf "type: %s\n" (Helper.get_string json "type");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: updated
    type: todo
    niceid: kb-0
  |}]

let%expect_test "bs update --json error not found" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["update"; "kb-999"; "--status"; "done"; "--json"] in
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

let%expect_test "bs update --json error nothing to update" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Title"]);
    let result = Helper.run_bs ~dir ["update"; "kb-0"; "--json"] in
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
    message: nothing to update
  |}]

let%expect_test "bs update errors on --content and stdin" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Title"]);
    let result = Helper.run_bs ~dir ~stdin:"Piped content"
      ["update"; "kb-0"; "--content"; "Flag content"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Cannot specify both --content and stdin input.
  |}]

let%expect_test "bs update --status does not hang on pipe stdin with no data" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Title"]);
    let result = Helper.run_bs_with_pipe_stdin ~dir ~timeout_s:2.0
      ["update"; "kb-0"; "--status"; "in-progress"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Updated todo: kb-0
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Title:  Title

    Body
  |}]

let%expect_test "bs update auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir
      ["update"; "kb-0"; "--status"; "in-progress"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Updated todo: kb-0
  |}]
