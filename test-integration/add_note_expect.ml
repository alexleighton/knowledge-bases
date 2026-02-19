module Helper = Test_helper

let%expect_test "bs add note succeeds" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
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
    Helper.init_kb dir;
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
    Helper.init_kb dir;
    let result =
      Helper.run_bs ~dir ~stdin:"Body text"
        ["add"; "note"; ""]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: title must be between 1 and 100 characters, got 0
  |}]

let%expect_test "bs add note rejects empty content" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result =
      Helper.run_bs ~dir
        ["add"; "note"; "A Title"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: content must be between 1 and 10000 characters, got 0
  |}]

let%expect_test "bs add note fails when not in git repo" =
  Helper.with_temp_dir ~name:"kb-add-no-git-" (fun dir ->
    let result =
      Helper.run_bs ~dir ~stdin:"Body"
        ["add"; "note"; "Orphan"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "bs add note fails when KB not initialised" =
  Helper.with_git_root (fun dir ->
    let result =
      Helper.run_bs ~dir ~stdin:"Body"
        ["add"; "note"; "Orphan"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No knowledge base found. Run 'bs init' first.
  |}]
