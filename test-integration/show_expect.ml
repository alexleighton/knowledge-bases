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
    Title:  First todo

    Body A

    Outgoing:
      depends-on  kb-1  todo  Second todo
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
    Title:  Second todo

    Body B

    Incoming:
      depends-on  kb-0  todo  First todo
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
    Title:  Task A

    Body

    Outgoing:
      related-to  kb-2  note  Design note

    Incoming:
      depends-on  kb-1  todo  Task B
  |}]

let%expect_test "bs show fails when KB not initialised" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No knowledge base found. Run 'bs init' first.
  |}]

let%expect_test "bs show --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Content here" ["add"; "todo"; "My item"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "type: %s\n" (Helper.get_string json "type");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid");
    Printf.printf "has typeid: %b\n" (Helper.get_string json "typeid" <> "<missing>");
    Printf.printf "status: %s\n" (Helper.get_string json "status");
    Printf.printf "title: %s\n" (Helper.get_string json "title");
    Printf.printf "content: %s\n" (Helper.get_string json "content");
    Printf.printf "outgoing count: %d\n" (List.length (Helper.get_list json "outgoing"));
    Printf.printf "incoming count: %d\n" (List.length (Helper.get_list json "incoming")));
  [%expect {|
    [exit 0]
    ok: true
    type: todo
    niceid: kb-0
    has typeid: true
    status: open
    title: My item
    content: Content here
    outgoing count: 0
    incoming count: 0
  |}]

let%expect_test "bs show --json with relations" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "todo"; "Item A"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "todo"; "Item B"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    let outgoing = Helper.get_list json "outgoing" in
    Printf.printf "outgoing count: %d\n" (List.length outgoing);
    List.iter (fun rel ->
      Printf.printf "  kind=%s niceid=%s type=%s\n"
        (Helper.get_string rel "kind")
        (Helper.get_string rel "niceid")
        (Helper.get_string rel "type")
    ) outgoing);
  [%expect {|
    [exit 0]
    outgoing count: 1
      kind=depends-on niceid=kb-1 type=todo
  |}]
