module Helper = Test_helper

let%expect_test "bs close open todo" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "Fix bug"]);
    let result = Helper.run_bs ~dir ["close"; "kb-0"] in
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

let%expect_test "bs close a note fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "Research"]);
    let result = Helper.run_bs ~dir ["close"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: resolve applies only to todos, but kb-0 is a note
  |}]

let%expect_test "bs close non-existent niceid" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["close"; "kb-999"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs close outside git repo" =
  Helper.with_temp_dir ~name:"kb-close-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["close"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]
