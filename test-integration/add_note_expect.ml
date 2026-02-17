module Helper = Test_helper

let init_kb dir =
  let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"] in
  if result.exit_code <> 0 then
    failwith ("init_kb setup failed: " ^ result.stderr)

let%expect_test "bs add note succeeds with --db-file" =
  Helper.with_git_root (fun dir ->
    init_kb dir;
    let db_file = Filename.concat dir ".kbases.db" in
    let result =
      Helper.run_bs ~dir ~stdin:"Hello world"
        ["add"; "note"; "My Note"; "--db-file"; db_file]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Created note: kb-0 (<TYPEID>)
  |}]

let%expect_test "bs add note auto-discovers database from git root" =
  Helper.with_git_root (fun dir ->
    init_kb dir;
    let result =
      Helper.run_bs ~dir ~stdin:"Some content"
        ["add"; "note"; "Auto Note"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Created note: kb-0 (<TYPEID>)
  |}]

let%expect_test "bs add note assigns sequential niceids" =
  Helper.with_git_root (fun dir ->
    init_kb dir;
    let r1 =
      Helper.run_bs ~dir ~stdin:"First note body"
        ["add"; "note"; "First"]
    in
    let r2 =
      Helper.run_bs ~dir ~stdin:"Second note body"
        ["add"; "note"; "Second"]
    in
    Helper.print_result ~dir r1;
    Helper.print_result ~dir r2);
  [%expect {|
    [exit 0]
    Created note: kb-0 (<TYPEID>)
    [exit 0]
    Created note: kb-1 (<TYPEID>)
  |}]

let%expect_test "bs add note rejects empty title" =
  Helper.with_git_root (fun dir ->
    init_kb dir;
    let result =
      Helper.run_bs ~dir ~stdin:"Body text"
        ["add"; "note"; ""; "--db-file"; Filename.concat dir ".kbases.db"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: title must be between 1 and 100 characters, got 0
  |}]

let%expect_test "bs add note rejects empty content" =
  Helper.with_git_root (fun dir ->
    init_kb dir;
    let result =
      Helper.run_bs ~dir
        ["add"; "note"; "A Title"; "--db-file"; Filename.concat dir ".kbases.db"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: content must be between 1 and 10000 characters, got 0
  |}]

let%expect_test "bs add note fails when database does not exist" =
  Helper.with_git_root (fun dir ->
    let result =
      Helper.run_bs ~dir ~stdin:"Body"
        ["add"; "note"; "Orphan"; "--db-file"; Filename.concat dir "missing.db"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No namespace configured. Set the 'namespace' config key.
  |}]
