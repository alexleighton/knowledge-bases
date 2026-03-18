module Helper = Test_helper

let%expect_test "bs show displays outgoing unidirectional relation" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "todo"; "First todo"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "todo"; "Second todo"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  First todo

    Body A

    Outgoing:
      depends-on  kb-1  todo  Second todo  [blocking]
    |}]

let%expect_test "bs show displays incoming unidirectional relation" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "todo"; "First todo"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "todo"; "Second todo"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["show"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    todo kb-1 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Second todo

    Body B

    Incoming:
      depends-on  kb-0  todo  First todo  [blocking]
    |}]

let%expect_test "bs show displays bidirectional relation as outgoing from source" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "A todo"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "A note"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--related-to"; "kb-1"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  A todo

    Body

    Outgoing:
      related-to  kb-1  note  A note
    |}]

let%expect_test "bs show displays bidirectional relation as outgoing from target" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "A todo"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "A note"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--related-to"; "kb-1"]);
    let result = Helper.run_bs ~dir ["show"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    note kb-1 (<TYPEID>)
    Status: active
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  A note

    Body

    Outgoing:
      related-to  kb-0  todo  A todo
    |}]

let%expect_test "bs show displays both outgoing and incoming relations" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task A"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task B"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Design note"]);
    (* kb-1 depends-on kb-0 (so kb-0 has incoming from kb-1) *)
    ignore (Helper.run_bs ~dir ["relate"; "kb-1"; "--depends-on"; "kb-0"]);
    (* kb-0 related-to kb-2 (outgoing from kb-0) *)
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--related-to"; "kb-2"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Task A

    Body

    Outgoing:
      related-to  kb-2  note  Design note

    Incoming:
      depends-on  kb-1  todo  Task B  [blocking]
    |}]

let%expect_test "bs show multiple identifiers" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "note"; "Second"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  First

    Body A
    ---
    note kb-1 (<TYPEID>)
    Status: active
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Second

    Body B
    |}]

let%expect_test "bs show multiple identifiers fails on missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Exists"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"; "kb-999"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-999
  |}]
