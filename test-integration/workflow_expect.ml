module Helper = Test_helper

let%expect_test "project planning — create, relate, progress, and list" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;

    (* Phase 1 — Seed the knowledge base *)
    ignore (Helper.run_bs ~dir ~stdin:"Architecture overview for the project."
      ["add"; "note"; "Architecture design"]);
    ignore (Helper.run_bs ~dir ~stdin:"Implement the storage and query layer."
      ["add"; "todo"; "Implement data layer"]);
    ignore (Helper.run_bs ~dir ~stdin:"Build REST endpoints for all entities."
      ["add"; "todo"; "Implement API endpoints"]);
    ignore (Helper.run_bs ~dir ~stdin:"Cover all endpoints with integration tests."
      ["add"; "todo"; "Write integration tests"]);
    ignore (Helper.run_bs ~dir ~stdin:"Target p99 < 50ms for all queries."
      ["add"; "note"; "Performance requirements"]);

    let list1 = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list1;

    (* Phase 2 — Establish relations *)
    ignore (Helper.run_bs ~dir ["relate"; "kb-1"; "--related-to"; "kb-0"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-2"; "--related-to"; "kb-0"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-3"; "--depends-on"; "kb-2"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-3"; "--depends-on"; "kb-1"]);

    let show_kb3 = Helper.run_bs ~dir ["show"; "kb-3"] in
    Helper.print_result ~dir show_kb3;

    (* Phase 3 — Work progresses *)
    ignore (Helper.run_bs ~dir ["update"; "kb-1"; "--status"; "in-progress"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-1"]);
    ignore (Helper.run_bs ~dir ["update"; "kb-2"; "--status"; "in-progress"]);

    let list2 = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list2;

    let done_todos = Helper.run_bs ~dir ["list"; "todo"; "--status"; "done"] in
    Helper.print_result ~dir done_todos;

    (* Phase 4 — Finish up *)
    ignore (Helper.run_bs ~dir ["resolve"; "kb-2"]);
    ignore (Helper.run_bs ~dir ["update"; "kb-3"; "--status"; "in-progress"]);
    ignore (Helper.run_bs ~dir ["archive"; "kb-4"]);

    let list3 = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list3);
  [%expect {|
    [exit 0]
    kb-0    note  active        Architecture design
    kb-1    todo  open          Implement data layer
    kb-2    todo  open          Implement API endpoints
    kb-3    todo  open          Write integration tests
    kb-4    note  active        Performance requirements
    [exit 0]
    todo kb-3 (<TYPEID>)
    Status: open
    Title:  Write integration tests

    Cover all endpoints with integration tests.

    Outgoing:
      depends-on  kb-1  todo  Implement data layer
      depends-on  kb-2  todo  Implement API endpoints
    [exit 0]
    kb-0    note  active        Architecture design
    kb-2    todo  in-progress   Implement API endpoints
    kb-3    todo  open          Write integration tests
    kb-4    note  active        Performance requirements
    [exit 0]
    kb-1    todo  done          Implement data layer
    [exit 0]
    kb-0    note  active        Architecture design
    kb-3    todo  in-progress   Write integration tests
    |}]

let%expect_test "flush-rebuild round trip preserves state" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;

    (* Phase 1 — Build state *)
    ignore (Helper.run_bs ~dir ~stdin:"Implement the first task."
      ["add"; "todo"; "First task"]);
    ignore (Helper.run_bs ~dir ~stdin:"Design document for the project."
      ["add"; "note"; "Design doc"]);
    ignore (Helper.run_bs ~dir ~stdin:"Implement the second task."
      ["add"; "todo"; "Second task"]);
    ignore (Helper.run_bs ~dir ["update"; "kb-0"; "--status"; "in-progress"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-2"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-2"; "--related-to"; "kb-1"]);

    let list1 = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list1;

    let show_kb0 = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show_kb0;

    let show_kb2 = Helper.run_bs ~dir ["show"; "kb-2"] in
    Helper.print_result ~dir show_kb2;

    (* Phase 2 — Rebuild from JSONL *)
    let rebuild = Helper.run_bs ~dir ["rebuild"] in
    Helper.print_result ~dir rebuild;

    let list2 = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list2;

    let show_kb1_post = Helper.run_bs ~dir ["show"; "kb-1"] in
    Helper.print_result ~dir show_kb1_post;

    (* Phase 3 — Operate on rebuilt state *)
    ignore (Helper.run_bs ~dir ["resolve"; "kb-1"]);

    let list3 = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list3);
  [%expect {|
    [exit 0]
    kb-0    todo  in-progress   First task
    kb-1    note  active        Design doc
    kb-2    todo  open          Second task
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Title:  First task

    Implement the first task.

    Outgoing:
      depends-on  kb-2  todo  Second task
    [exit 0]
    todo kb-2 (<TYPEID>)
    Status: open
    Title:  Second task

    Implement the second task.

    Outgoing:
      related-to  kb-1  note  Design doc

    Incoming:
      depends-on  kb-0  todo  First task
    [exit 0]
    Rebuilt SQLite from .kbases.jsonl
    [exit 0]
    kb-0    note  active        Design doc
    kb-1    todo  in-progress   First task
    kb-2    todo  open          Second task
    [exit 0]
    todo kb-1 (<TYPEID>)
    Status: in-progress
    Title:  First task

    Implement the first task.

    Outgoing:
      depends-on  kb-2  todo  Second task
    [exit 0]
    kb-0    note  active        Design doc
    kb-2    todo  open          Second task
    |}]

let%expect_test "iterative refinement — update items multiple times" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;

    (* Phase 1 — Create and refine *)
    ignore (Helper.run_bs ~dir ~stdin:"Initial auth implementation plan."
      ["add"; "todo"; "Draft: implement auth"]);
    ignore (Helper.run_bs ~dir ~stdin:"Initial logging implementation plan."
      ["add"; "todo"; "Draft: implement logging"]);
    ignore (Helper.run_bs ~dir
      ["update"; "kb-0"; "--title"; "Implement authentication"]);
    ignore (Helper.run_bs ~dir
      ["update"; "kb-1"; "--title"; "Add structured logging";
       "--status"; "in-progress"]);

    let list1 = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list1;

    (* Phase 2 — Content revisions *)
    ignore (Helper.run_bs ~dir ~stdin:"Use OAuth2 for all endpoints."
      ["update"; "kb-0"; "--content"]);
    ignore (Helper.run_bs ~dir
      ["update"; "kb-0"; "--status"; "in-progress"]);
    ignore (Helper.run_bs ~dir ~stdin:"Use slog library with JSON output."
      ["update"; "kb-1"; "--content"]);

    let show_kb0 = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show_kb0;

    let show_kb1 = Helper.run_bs ~dir ["show"; "kb-1"] in
    Helper.print_result ~dir show_kb1;

    (* Phase 3 — Resolve, add, relate *)
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    ignore (Helper.run_bs ~dir ~stdin:"Decided on OAuth2 with PKCE flow."
      ["add"; "note"; "Auth design decisions"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-2"; "--related-to"; "kb-0"]);

    let show_kb2 = Helper.run_bs ~dir ["show"; "kb-2"] in
    Helper.print_result ~dir show_kb2;

    let list2 = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list2;

    let done_todos = Helper.run_bs ~dir ["list"; "todo"; "--status"; "done"] in
    Helper.print_result ~dir done_todos);
  [%expect {|
    [exit 0]
    kb-0    todo  open          Implement authentication
    kb-1    todo  in-progress   Add structured logging
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Title:  Implement authentication

    Use OAuth2 for all endpoints.
    [exit 0]
    todo kb-1 (<TYPEID>)
    Status: in-progress
    Title:  Add structured logging

    Use slog library with JSON output.
    [exit 0]
    note kb-2 (<TYPEID>)
    Status: active
    Title:  Auth design decisions

    Decided on OAuth2 with PKCE flow.

    Outgoing:
      related-to  kb-0  todo  Implement authentication
    [exit 0]
    kb-1    todo  in-progress   Add structured logging
    kb-2    note  active        Auth design decisions
    [exit 0]
    kb-0    todo  done          Implement authentication
    |}]
