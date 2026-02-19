module Helper = Test_helper

let%expect_test "bs add todo succeeds with --db-file" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let db_file = Filename.concat dir ".kbases.db" in
    let result =
      Helper.run_bs ~dir ~stdin:"Fix the bug"
        ["add"; "todo"; "Bug report"; "--db-file"; db_file]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Created todo: kb-0 (<TYPEID>)
  |}]

let%expect_test "bs add todo auto-discovers database from git root" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result =
      Helper.run_bs ~dir ~stdin:"Some content"
        ["add"; "todo"; "Auto Todo"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Created todo: kb-0 (<TYPEID>)
  |}]

let%expect_test "bs add todo assigns sequential niceids" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let r1 =
      Helper.run_bs ~dir ~stdin:"First todo body"
        ["add"; "todo"; "First"]
    in
    let r2 =
      Helper.run_bs ~dir ~stdin:"Second todo body"
        ["add"; "todo"; "Second"]
    in
    Helper.print_result ~dir r1;
    Helper.print_result ~dir r2);
  [%expect {|
    [exit 0]
    Created todo: kb-0 (<TYPEID>)
    [exit 0]
    Created todo: kb-1 (<TYPEID>)
  |}]

let%expect_test "bs add todo rejects empty title" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result =
      Helper.run_bs ~dir ~stdin:"Body text"
        ["add"; "todo"; ""; "--db-file"; Filename.concat dir ".kbases.db"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: title must be between 1 and 100 characters, got 0
  |}]

let%expect_test "bs add todo rejects empty content" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result =
      Helper.run_bs ~dir
        ["add"; "todo"; "A Title"; "--db-file"; Filename.concat dir ".kbases.db"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: content must be between 1 and 10000 characters, got 0
  |}]

let%expect_test "bs add todo fails when database does not exist" =
  Helper.with_git_root (fun dir ->
    let result =
      Helper.run_bs ~dir ~stdin:"Body"
        ["add"; "todo"; "Orphan"; "--db-file"; Filename.concat dir "missing.db"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No namespace configured. Set the 'namespace' config key.
  |}]
