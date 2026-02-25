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
    kb-0    todo  open          Todo item
    kb-1    note  active        Note item
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
    kb-0    todo  open          Todo item
    kb-1    note  active        Note item
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
    STDERR: Usage: bs list [--help] [--status=STATUS] [OPTION]… [TYPE]
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
    STDERR: Usage: bs list [--help] [--status=STATUS] [OPTION]… [TYPE]
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

let%expect_test "bs list fails when KB not initialised" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No knowledge base found. Run 'bs init' first.
  |}]
