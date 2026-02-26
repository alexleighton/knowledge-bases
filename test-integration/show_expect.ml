module Helper = Test_helper

let%expect_test "bs show todo by niceid" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Todo title"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Title:  Todo title

    Todo body
  |}]

let%expect_test "bs show note by niceid" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Note title"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    note kb-0 (<TYPEID>)
    Status: active
    Title:  Note title

    Note body
  |}]

let%expect_test "bs show by typeid" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let add_result = Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Todo title"] in
    (* Extract the raw TypeId from the add output before normalisation.
       The add output is: "Created todo: kb-0 (todo_...)\n" *)
    let raw_stdout = add_result.stdout in
    let typeid_str =
      let open_paren = String.index raw_stdout '(' in
      let close_paren = String.index raw_stdout ')' in
      String.sub raw_stdout (open_paren + 1) (close_paren - open_paren - 1)
    in
    let result = Helper.run_bs ~dir ["show"; typeid_str] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Title:  Todo title

    Todo body
  |}]

let%expect_test "bs show niceid not found" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["show"; "kb-999"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs show typeid not found" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["show"; "todo_00000000000000000000000000"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: <TYPEID>
  |}]

let%expect_test "bs show invalid identifier" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["show"; "garbage"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: invalid identifier "garbage" — expected a niceid (e.g. kb-0) or typeid (e.g. <TYPEID>...)
  |}]

let%expect_test "bs show fails when not in git repo" =
  Helper.with_temp_dir ~name:"kb-show-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "bs show fails when KB not initialised" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No knowledge base found. Run 'bs init' first.
  |}]
