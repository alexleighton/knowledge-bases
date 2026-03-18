module Helper = Test_helper

let%expect_test "bs delete single item" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    let result = Helper.run_bs ~dir ["delete"; "kb-0"] in
    Helper.print_result ~dir result;
    let list = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list);
  [%expect {|
    [exit 0]
    Deleted todo: kb-0
    [exit 0]
    |}]

let%expect_test "bs delete multiple items" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task 1"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Note 1"]);
    let result = Helper.run_bs ~dir ["delete"; "kb-0"; "kb-1"] in
    Helper.print_result ~dir result;
    let list = Helper.run_bs ~dir ["list"; "--status"; "open";
                                   "--status"; "active"] in
    Helper.print_result ~dir list);
  [%expect {|
    [exit 0]
    Deleted todo: kb-0
    Deleted note: kb-1
    [exit 0]
    |}]

let%expect_test "bs delete blocked item fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocker"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Depends";
            "--depends-on"; "kb-0"]);
    let result = Helper.run_bs ~dir ["delete"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: cannot delete kb-0: blocked by kb-1
  |}]

let%expect_test "bs delete --force bypasses blocking" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocker"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Depends";
            "--depends-on"; "kb-0"]);
    let result = Helper.run_bs ~dir ["delete"; "kb-0"; "--force"] in
    Helper.print_result ~dir result;
    (* Verify the dependent item still exists and its relation is gone *)
    let show = Helper.run_bs ~dir ["show"; "kb-1"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Deleted todo: kb-0
    [exit 0]
    todo kb-1 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Depends

    Body
    |}]

let%expect_test "bs delete non-existent item" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["delete"; "kb-999"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs delete --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    let result = Helper.run_bs ~dir ["delete"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let deleted = Helper.get_list json "deleted" in
    Printf.printf "deleted count: %d\n" (List.length deleted);
    let item = List.hd deleted in
    Printf.printf "type: %s\n" (Helper.get_string item "type");
    Printf.printf "niceid: %s\n" (Helper.get_string item "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    deleted count: 1
    type: todo
    niceid: kb-0
  |}]

let%expect_test "bs delete auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["delete"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Deleted todo: kb-0
  |}]
