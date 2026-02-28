module Helper = Test_helper

let parse_json stdout =
  try Yojson.Safe.from_string stdout
  with Yojson.Json_error msg ->
    Printf.printf "JSON parse error: %s\n" msg;
    `Null

let get_string json key =
  match json with
  | `Assoc pairs -> (
      match List.assoc_opt key pairs with
      | Some (`String s) -> s
      | _ -> "<missing>")
  | _ -> "<not-object>"

let get_bool json key =
  match json with
  | `Assoc pairs -> (
      match List.assoc_opt key pairs with
      | Some (`Bool b) -> b
      | _ -> false)
  | _ -> false

let get_list json key =
  match json with
  | `Assoc pairs -> (
      match List.assoc_opt key pairs with
      | Some (`List l) -> l
      | _ -> [])
  | _ -> []

let%expect_test "bs init --json" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "has directory: %b\n" (get_string json "directory" <> "<missing>");
    Printf.printf "namespace: %s\n" (get_string json "namespace");
    Printf.printf "has db_file: %b\n" (get_string json "db_file" <> "<missing>");
    Printf.printf "agents_md: %s\n" (get_string json "agents_md");
    Printf.printf "git_exclude: %s\n" (get_string json "git_exclude"));
  [%expect {|
    [exit 0]
    ok: true
    has directory: true
    namespace: kb
    has db_file: true
    agents_md: created
    git_exclude: added to .git/info/exclude
  |}]

let%expect_test "bs add todo --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "My todo"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "type: %s\n" (get_string json "type");
    Printf.printf "niceid: %s\n" (get_string json "niceid");
    Printf.printf "has typeid: %b\n" (get_string json "typeid" <> "<missing>"));
  [%expect {|
    [exit 0]
    ok: true
    type: todo
    niceid: kb-0
    has typeid: true
  |}]

let%expect_test "bs add note --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "My note"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "type: %s\n" (get_string json "type");
    Printf.printf "niceid: %s\n" (get_string json "niceid");
    Printf.printf "has typeid: %b\n" (get_string json "typeid" <> "<missing>"));
  [%expect {|
    [exit 0]
    ok: true
    type: note
    niceid: kb-0
    has typeid: true
  |}]

let%expect_test "bs list --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Second"]);
    let result = Helper.run_bs ~dir ["list"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    let items = get_list json "items" in
    Printf.printf "item count: %d\n" (List.length items);
    List.iter (fun item ->
      Printf.printf "  niceid=%s type=%s status=%s title=%s\n"
        (get_string item "niceid")
        (get_string item "type")
        (get_string item "status")
        (get_string item "title")
    ) items);
  [%expect {|
    [exit 0]
    ok: true
    item count: 2
      niceid=kb-0 type=todo status=open title=First
      niceid=kb-1 type=note status=active title=Second
  |}]

let%expect_test "bs list --json empty" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "item count: %d\n" (List.length (get_list json "items")));
  [%expect {|
    [exit 0]
    ok: true
    item count: 0
  |}]

let%expect_test "bs show --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Content here" ["add"; "todo"; "My item"]);
    let result = Helper.run_bs ~dir ["show"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "type: %s\n" (get_string json "type");
    Printf.printf "niceid: %s\n" (get_string json "niceid");
    Printf.printf "has typeid: %b\n" (get_string json "typeid" <> "<missing>");
    Printf.printf "status: %s\n" (get_string json "status");
    Printf.printf "title: %s\n" (get_string json "title");
    Printf.printf "content: %s\n" (get_string json "content");
    Printf.printf "outgoing count: %d\n" (List.length (get_list json "outgoing"));
    Printf.printf "incoming count: %d\n" (List.length (get_list json "incoming")));
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
    let json = parse_json result.stdout in
    let outgoing = get_list json "outgoing" in
    Printf.printf "outgoing count: %d\n" (List.length outgoing);
    List.iter (fun rel ->
      Printf.printf "  kind=%s niceid=%s type=%s\n"
        (get_string rel "kind")
        (get_string rel "niceid")
        (get_string rel "type")
    ) outgoing);
  [%expect {|
    [exit 0]
    outgoing count: 1
      kind=depends-on niceid=kb-1 type=todo
  |}]

let%expect_test "bs update --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    let result = Helper.run_bs ~dir ["update"; "kb-0"; "--status"; "in-progress"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "action: %s\n" (get_string json "action");
    Printf.printf "type: %s\n" (get_string json "type");
    Printf.printf "niceid: %s\n" (get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: updated
    type: todo
    niceid: kb-0
  |}]

let%expect_test "bs resolve --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    let result = Helper.run_bs ~dir ["resolve"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "action: %s\n" (get_string json "action");
    Printf.printf "type: %s\n" (get_string json "type");
    Printf.printf "niceid: %s\n" (get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: resolved
    type: todo
    niceid: kb-0
  |}]

let%expect_test "bs close --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "My todo"]);
    let result = Helper.run_bs ~dir ["close"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "action: %s\n" (get_string json "action");
    Printf.printf "type: %s\n" (get_string json "type");
    Printf.printf "niceid: %s\n" (get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: resolved
    type: todo
    niceid: kb-0
  |}]

let%expect_test "bs archive --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "My note"]);
    let result = Helper.run_bs ~dir ["archive"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "action: %s\n" (get_string json "action");
    Printf.printf "type: %s\n" (get_string json "type");
    Printf.printf "niceid: %s\n" (get_string json "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    action: archived
    type: note
    niceid: kb-0
  |}]

let%expect_test "bs relate --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body A" ["add"; "todo"; "Item A"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body B" ["add"; "todo"; "Item B"]);
    let result = Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-1"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "source: %s\n" (get_string json "source");
    Printf.printf "kind: %s\n" (get_string json "kind");
    Printf.printf "target: %s\n" (get_string json "target");
    Printf.printf "directionality: %s\n" (get_string json "directionality"));
  [%expect {|
    [exit 0]
    ok: true
    source: kb-0
    kind: depends-on
    target: kb-1
    directionality: unidirectional
  |}]

let%expect_test "bs flush --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Item"]);
    let result = Helper.run_bs ~dir ["flush"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "action: %s\n" (get_string json "action");
    Printf.printf "file: %s\n" (get_string json "file"));
  [%expect {|
    [exit 0]
    ok: true
    action: flushed
    file: .kbases.jsonl
  |}]

let%expect_test "bs rebuild --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Item"]);
    ignore (Helper.run_bs ~dir ["flush"]);
    let result = Helper.run_bs ~dir ["rebuild"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = parse_json result.stdout in
    Printf.printf "ok: %b\n" (get_bool json "ok");
    Printf.printf "action: %s\n" (get_string json "action");
    Printf.printf "file: %s\n" (get_string json "file"));
  [%expect {|
    [exit 0]
    ok: true
    action: rebuilt
    file: .kbases.jsonl
  |}]
