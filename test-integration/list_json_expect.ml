module Helper = Test_helper

let%expect_test "bs list --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "note"; "Second"]);
    let result = Helper.run_bs ~dir ["list"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let items = Helper.get_list json "items" in
    Printf.printf "item count: %d\n" (List.length items);
    List.iter (fun item ->
      Printf.printf "  niceid=%s type=%s status=%s title=%s\n"
        (Helper.get_string item "niceid")
        (Helper.get_string item "type")
        (Helper.get_string item "status")
        (Helper.get_string item "title")
    ) items);
  [%expect {|
    [exit 0]
    ok: true
    item count: 2
      niceid=kb-1 type=note status=active title=Second
      niceid=kb-0 type=todo status=open title=First
    |}]

let%expect_test "bs list --json empty" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "item count: %d\n" (List.length (Helper.get_list json "items")));
  [%expect {|
    [exit 0]
    ok: true
    item count: 0
  |}]

let%expect_test "bs list --json error invalid status for type" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "note"; "--status"; "done"; "--json"] in
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

let%expect_test "bs list --json error --available with --status" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "--available"; "--status"; "open"; "--json"] in
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
    message: --available cannot be combined with --status
  |}]

let%expect_test "bs list --json error --available with notes" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["list"; "note"; "--available"; "--json"] in
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
    message: --available applies only to todos, not notes
  |}]

let%expect_test "bs list --available --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Available"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Blocked"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-1"; "--depends-on"; "kb-0"; "--blocking"]);
    let result = Helper.run_bs ~dir ["list"; "--available"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let items = Helper.get_list json "items" in
    Printf.printf "item count: %d\n" (List.length items);
    List.iter (fun item ->
      Printf.printf "  niceid=%s type=%s status=%s title=%s\n"
        (Helper.get_string item "niceid")
        (Helper.get_string item "type")
        (Helper.get_string item "status")
        (Helper.get_string item "title")
    ) items);
  [%expect {|
    [exit 0]
    ok: true
    item count: 1
      niceid=kb-0 type=todo status=open title=Available
  |}]
