module Helper = Test_helper

let%expect_test "bs add todo succeeds" =
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
        ["add"; "todo"; ""]
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
        ["add"; "todo"; "A Title"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No content provided. Use --content or pipe content to stdin.
  |}]

let%expect_test "bs add todo fails when not in git repo" =
  Helper.with_temp_dir ~name:"kb-add-no-git-" (fun dir ->
    let result =
      Helper.run_bs ~dir ~stdin:"Body"
        ["add"; "todo"; "Orphan"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "bs add todo fails when KB not initialised" =
  Helper.with_git_root (fun dir ->
    let result =
      Helper.run_bs ~dir ~stdin:"Body"
        ["add"; "todo"; "Orphan"]
    in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: No knowledge base found. Run 'bs init' first.
  |}]

let%expect_test "bs add todo --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "My todo"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "type: %s\n" (Helper.get_string json "type");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid");
    Printf.printf "has typeid: %b\n" (Helper.get_string json "typeid" <> "<missing>"));
  [%expect {|
    [exit 0]
    ok: true
    type: todo
    niceid: kb-0
    has typeid: true
  |}]

let%expect_test "bs add todo with --related-to" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    let result = Helper.run_bs ~dir ~stdin:"Body"
      ["add"; "todo"; "Task"; "--related-to"; "kb-0"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Created todo: kb-1 (<TYPEID>)
      related-to  kb-0  todo  First
  |}]

let%expect_test "bs add todo with --depends-on invalid target" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    let result = Helper.run_bs ~dir ~stdin:"Body"
      ["add"; "todo"; "Task"; "--depends-on"; "kb-99"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: item not found: kb-99
  |}]

let%expect_test "bs add todo with multiple relation flags" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Second"]);
    let result = Helper.run_bs ~dir ~stdin:"Body"
      ["add"; "todo"; "Task"; "--related-to"; "kb-0"; "--depends-on"; "kb-1"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Created todo: kb-2 (<TYPEID>)
      depends-on  kb-1  todo  Second
      related-to  kb-0  todo  First
  |}]

let%expect_test "bs add todo with --related-to --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    let result = Helper.run_bs ~dir ~stdin:"Body"
      ["add"; "todo"; "Task"; "--related-to"; "kb-0"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "type: %s\n" (Helper.get_string json "type");
    Printf.printf "niceid: %s\n" (Helper.get_string json "niceid");
    let relations = Helper.get_list json "relations" in
    Printf.printf "relations count: %d\n" (List.length relations);
    let r = List.nth relations 0 in
    Printf.printf "rel kind: %s\n" (Helper.get_string r "kind");
    Printf.printf "rel niceid: %s\n" (Helper.get_string r "niceid"));
  [%expect {|
    [exit 0]
    ok: true
    type: todo
    niceid: kb-1
    relations count: 1
    rel kind: related-to
    rel niceid: kb-0
  |}]

let%expect_test "bs add todo --json error empty title" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ~stdin:"Body"
      ["add"; "todo"; ""; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    if result.stderr = "" then print_endline "stderr empty: true"
    else Printf.printf "unexpected stderr: %s\n" result.stderr;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason"));
  [%expect {|
    [exit 1]
    stderr empty: true
    ok: false
    reason: error
  |}]

let%expect_test "bs add todo --json error no content" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["add"; "todo"; "Title"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    if result.stderr = "" then print_endline "stderr empty: true"
    else Printf.printf "unexpected stderr: %s\n" result.stderr;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason");
    Printf.printf "message: %s\n" (Helper.get_string json "message"));
  [%expect {|
    [exit 1]
    stderr empty: true
    ok: false
    reason: error
    message: No content provided. Use --content or pipe content to stdin.
  |}]

let%expect_test "bs add todo --json error invalid relation target" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ~stdin:"Body"
      ["add"; "todo"; "Task"; "--depends-on"; "kb-99"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    if result.stderr = "" then print_endline "stderr empty: true"
    else Printf.printf "unexpected stderr: %s\n" result.stderr;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason");
    Printf.printf "message: %s\n" (Helper.get_string json "message"));
  [%expect {|
    [exit 1]
    stderr empty: true
    ok: false
    reason: error
    message: item not found: kb-99
  |}]

let%expect_test "bs add todo with --content flag" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir
      ["add"; "todo"; "Flag todo"; "--content"; "Body from flag"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Created todo: kb-0 (<TYPEID>)
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Flag todo

    Body from flag
    |}]

let%expect_test "bs add todo errors on --content and stdin" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ~stdin:"From pipe"
      ["add"; "todo"; "Title"; "--content"; "From flag"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Cannot specify both --content and stdin input.
  |}]

let%expect_test "bs add todo --content does not hang on pipe stdin with no data" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs_with_pipe_stdin ~dir ~timeout_s:2.0
      ["add"; "todo"; "Title"; "--content"; "From flag"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Created todo: kb-0 (<TYPEID>)
  |}]

let%expect_test "bs add todo with --related-to --blocking" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "First"]);
    let result = Helper.run_bs ~dir ~stdin:"Body"
      ["add"; "todo"; "Task"; "--related-to"; "kb-0"; "--blocking"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Created todo: kb-1 (<TYPEID>)
      related-to  kb-0  todo  First
  |}]

let%expect_test "bs add todo auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"First body" ["add"; "todo"; "First"]);
    Helper.delete_db dir;
    let add_result = Helper.run_bs ~dir ~stdin:"Second body"
      ["add"; "todo"; "Second"] in
    Helper.print_result ~dir add_result;
    let list_result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list_result);
  [%expect {|
    [exit 0]
    Created todo: kb-1 (<TYPEID>)
    [exit 0]
    kb-1    todo  open          Second
    kb-0    todo  open          First
    |}]
