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
    let relations = Helper.get_list json "relations" in
    Printf.printf "count: %d\n" (List.length relations);
    let r = List.nth relations 0 in
    Printf.printf "source: %s\n" (Helper.get_string r "source");
    Printf.printf "kind: %s\n" (Helper.get_string r "kind");
    Printf.printf "target: %s\n" (Helper.get_string r "target");
    Printf.printf "directionality: %s\n" (Helper.get_string r "directionality"));
  [%expect {|
    [exit 0]
    ok: true
    count: 1
    source: kb-0
    kind: depends-on
    target: kb-1
    directionality: unidirectional
  |}]

let%expect_test "bs relate with multiple --depends-on flags" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Second"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Third"]);
    let result = Helper.run_bs ~dir
      ["relate"; "kb-0"; "--depends-on"; "kb-1"; "--depends-on"; "kb-2"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Related: kb-0 depends-on kb-1 (unidirectional)
    Related: kb-0 depends-on kb-2 (unidirectional)
  |}]

let%expect_test "bs relate with mixed flags" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Source"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Dep"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Related"]);
    let result = Helper.run_bs ~dir
      ["relate"; "kb-0"; "--depends-on"; "kb-1"; "--related-to"; "kb-2"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Related: kb-0 depends-on kb-1 (unidirectional)
    Related: kb-0 related-to kb-2 (bidirectional)
  |}]

let%expect_test "bs relate atomic failure leaves no relations" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Source"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Valid"]);
    let result = Helper.run_bs ~dir
      ["relate"; "kb-0"; "--depends-on"; "kb-99"; "--related-to"; "kb-1"] in
    Helper.print_result ~dir result;
    let show_result = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show_result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-99
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Title:  Source

    Body
  |}]

let%expect_test "bs relate auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Source"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Target"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir
      ["relate"; "kb-0"; "--related-to"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Related: kb-0 related-to kb-1 (bidirectional)
  |}]
