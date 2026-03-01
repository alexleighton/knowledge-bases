module Helper = Test_helper

let%expect_test "bs relate with --depends-on" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First todo"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Second todo"]);
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Related: kb-0 depends-on kb-1 (unidirectional)
  |}]

let%expect_test "bs relate with --related-to" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "A todo"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "A note"]);
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--related-to"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Related: kb-0 related-to kb-1 (bidirectional)
  |}]

let%expect_test "bs relate with --uni" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Design"]);
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--uni"; "designed-by,kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Related: kb-0 designed-by kb-1 (unidirectional)
  |}]

let%expect_test "bs relate with --bi" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Second"]);
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--bi"; "reviews,kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Related: kb-0 reviews kb-1 (bidirectional)
  |}]

let%expect_test "bs relate source not found" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Target"]);
    let result = Helper.run_bs ~dir ["relate"; "kb-999"; "--depends-on"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs relate target not found" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Source"]);
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-999"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]

let%expect_test "bs relate duplicate" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Second"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: relation already exists
  |}]

let%expect_test "bs relate outside git repo" =
  Helper.with_temp_dir ~name:"kb-relate-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "bs relate when KB not initialised" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No knowledge base found. Run 'bs init' first.
  |}]

let%expect_test "bs relate --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "todo"; "Item A"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "todo"; "Item B"]);
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "source: %s\n" (Helper.get_string json "source");
    Printf.printf "kind: %s\n" (Helper.get_string json "kind");
    Printf.printf "target: %s\n" (Helper.get_string json "target");
    Printf.printf "directionality: %s\n" (Helper.get_string json "directionality"));
  [%expect {|
    [exit 0]
    ok: true
    source: kb-0
    kind: depends-on
    target: kb-1
    directionality: unidirectional
  |}]
