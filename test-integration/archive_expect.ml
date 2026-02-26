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
    Title:  Research

    Note body
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
