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

let%expect_test "bs update content from stdin" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Old body" ["add"; "todo"; "Title"]);
    let result = Helper.run_bs ~dir ~stdin:"New body" ["update"; "kb-0"; "--content"] in
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

let%expect_test "bs update multiple fields at once" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Old body" ["add"; "todo"; "Old title"]);
    let result = Helper.run_bs ~dir ~stdin:"New body"
      ["update"; "kb-0"; "--status"; "in-progress"; "--title"; "New title"; "--content"] in
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
