module Helper = Test_helper

let%expect_test "bs show --json returns all item fields" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Content here" ["add"; "todo"; "My item"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let items = Helper.get_list json "items" in
    Printf.printf "items count: %d\n" (List.length items);
    let item = List.hd items in
    Printf.printf "type: %s\n" (Helper.get_string item "type");
    Printf.printf "niceid: %s\n" (Helper.get_string item "niceid");
    Printf.printf "has typeid: %b\n" (Helper.get_string item "typeid" <> "<missing>");
    Printf.printf "status: %s\n" (Helper.get_string item "status");
    Printf.printf "title: %s\n" (Helper.get_string item "title");
    Printf.printf "content: %s\n" (Helper.get_string item "content");
    Printf.printf "outgoing count: %d\n" (List.length (Helper.get_list item "outgoing"));
    Printf.printf "incoming count: %d\n" (List.length (Helper.get_list item "incoming")));
  [%expect {|
    [exit 0]
    ok: true
    items count: 1
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
    let item = List.hd (Helper.get_list json "items") in
    let outgoing = Helper.get_list item "outgoing" in
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

let%expect_test "bs show multiple identifiers --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "note"; "Second"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"; "kb-1"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let items = Helper.get_list json "items" in
    Printf.printf "items count: %d\n" (List.length items);
    List.iter (fun item ->
      Printf.printf "  %s %s\n"
        (Helper.get_string item "type")
        (Helper.get_string item "niceid")
    ) items);
  [%expect {|
    [exit 0]
    ok: true
    items count: 2
      todo kb-0
      note kb-1
  |}]

let%expect_test "bs show --json error not found" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["show"; "kb-999"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    Printf.printf "stderr empty: %b\n" (result.stderr = "");
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason");
    Printf.printf "message: %s\n" (Helper.get_string json "message"));
  [%expect {|
    [exit 1]
    stderr empty: true
    ok: false
    reason: error
    message: item not found: kb-999
  |}]

let%expect_test "bs show --json error invalid identifier" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["show"; "garbage"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    Printf.printf "stderr empty: %b\n" (result.stderr = "");
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason"));
  [%expect {|
    [exit 1]
    stderr empty: true
    ok: false
    reason: error
  |}]

let%expect_test "bs show --json includes blocking field" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "todo"; "Source"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "todo"; "Target"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    let item = List.hd (Helper.get_list json "items") in
    let outgoing = Helper.get_list item "outgoing" in
    List.iter (fun rel ->
      Printf.printf "  kind=%s blocking=%b\n"
        (Helper.get_string rel "kind")
        (Helper.get_bool rel "blocking")
    ) outgoing);
  [%expect {|
    [exit 0]
      kind=depends-on blocking=true
  |}]
