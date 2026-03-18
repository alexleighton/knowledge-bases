module Helper = Test_helper

let%expect_test "bs list shows todos and notes" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Todo item"]);
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Note item"]);
    let result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    kb-1    note  active        Note item
    kb-0    todo  open          Todo item
    |}]

let%expect_test "bs list filters by type" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Todo item"]);
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Note item"]);
    let todos = Helper.run_bs ~dir ["list"; "todo"] in
    let notes = Helper.run_bs ~dir ["list"; "note"] in
    Helper.print_result ~dir todos;
    Helper.print_result ~dir notes);
  [%expect {|
    [exit 0]
    kb-0    todo  open          Todo item
    [exit 0]
    kb-1    note  active        Note item
  |}]

let%expect_test "bs list filters by status" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Todo item"]);
    let open_todos = Helper.run_bs ~dir ["list"; "todo"; "--status"; "open"] in
    Helper.print_result ~dir open_todos);
  [%expect {|
    [exit 0]
    kb-0    todo  open          Todo item
  |}]

let%expect_test "bs list supports multiple statuses" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Todo item"]);
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Note item"]);
    let result = Helper.run_bs ~dir ["list"; "--status"; "open"; "--status"; "active"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    kb-1    note  active        Note item
    kb-0    todo  open          Todo item
    |}]

let%expect_test "bs list rejects invalid status for type" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "note"; "--status"; "done"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: invalid status "done" for note
  |}]

let%expect_test "bs list rejects invalid status value" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "--status"; "banana"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 124]
    STDERR: Usage: bs list [--help] [OPTION]… [TYPE]
    bs: option '--status': invalid value 'banana', expected one of 'open',
        'in-progress', 'done', 'active' or 'archived'
    |}]

let%expect_test "bs list on empty KB" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
  |}]

let%expect_test "bs list --status open without type shows only todos" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Todo item"]);
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Note item"]);
    let result = Helper.run_bs ~dir ["list"; "--status"; "open"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    kb-0    todo  open          Todo item
  |}]

let%expect_test "bs list rejects invalid type argument" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "banana"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 124]
    STDERR: Usage: bs list [--help] [OPTION]… [TYPE]
    bs: TYPE argument: invalid value 'banana', expected either 'todo' or 'note'
    |}]

let%expect_test "bs list fails when not in git repo" =
  Helper.with_temp_dir ~name:"kb-list-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "bs list excludes done todos by default" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "todo"; "Todo A"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "todo"; "Todo B"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    let list_default = Helper.run_bs ~dir ["list"] in
    let list_done = Helper.run_bs ~dir ["list"; "--status"; "done"] in
    Helper.print_result ~dir list_default;
    Helper.print_result ~dir list_done);
  [%expect {|
    [exit 0]
    kb-1    todo  open          Todo B
    [exit 0]
    kb-0    todo  done          Todo A
    |}]

let%expect_test "bs list excludes archived notes by default" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "note"; "Note A"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "note"; "Note B"]);
    ignore (Helper.run_bs ~dir ["archive"; "kb-0"]);
    let list_default = Helper.run_bs ~dir ["list"] in
    let list_archived = Helper.run_bs ~dir ["list"; "--status"; "archived"] in
    Helper.print_result ~dir list_default;
    Helper.print_result ~dir list_archived);
  [%expect {|
    [exit 0]
    kb-1    note  active        Note B
    [exit 0]
    kb-0    note  archived      Note A
    |}]

let%expect_test "bs list fails when KB not initialised" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No knowledge base found. Run 'bs init' first.
  |}]

let%expect_test "bs list auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "My note"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    kb-1    todo  open          My todo
    kb-0    note  active        My note
    |}]

let%expect_test "bs list --available shows only unblocked open todos" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Unblocked"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocked"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Dependency"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-1"; "--depends-on"; "kb-2"; "--blocking"]);
    let result = Helper.run_bs ~dir ["list"; "--available"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    kb-2    todo  open          Dependency
    kb-0    todo  open          Unblocked
    |}]

let%expect_test "bs list todo --available works" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Open todo"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Active note"]);
    let result = Helper.run_bs ~dir ["list"; "todo"; "--available"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    kb-0    todo  open          Open todo
  |}]

let%expect_test "bs list --available --status is an error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "--available"; "--status"; "open"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: --available cannot be combined with --status
  |}]

let%expect_test "bs list note --available is an error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "note"; "--available"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: --available applies only to todos, not notes
  |}]
