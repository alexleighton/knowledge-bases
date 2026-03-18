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
    kb-4    note  active        Performance requirements
    kb-3    todo  open          Write integration tests
    kb-2    todo  open          Implement API endpoints
    kb-1    todo  open          Implement data layer
    kb-0    note  active        Architecture design
    [exit 0]
    todo kb-3 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Write integration tests

    Cover all endpoints with integration tests.

    Outgoing:
      depends-on  kb-1  todo  Implement data layer  [blocking]
      depends-on  kb-2  todo  Implement API endpoints  [blocking]
    [exit 0]
    kb-4    note  active        Performance requirements
    kb-3    todo  open          Write integration tests
    kb-2    todo  in-progress   Implement API endpoints
    kb-0    note  active        Architecture design
    [exit 0]
    kb-1    todo  done          Implement data layer
    [exit 0]
    kb-3    todo  in-progress   Write integration tests
    kb-0    note  active        Architecture design
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
    ignore (Helper.run_bs ~dir
      ["update"; "kb-0"; "--content"; "Use OAuth2 for all endpoints."]);
    ignore (Helper.run_bs ~dir
      ["update"; "kb-0"; "--status"; "in-progress"]);
    ignore (Helper.run_bs ~dir
      ["update"; "kb-1"; "--content"; "Use slog library with JSON output."]);

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
    kb-1    todo  in-progress   Add structured logging
    kb-0    todo  open          Implement authentication
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Implement authentication

    Use OAuth2 for all endpoints.
    [exit 0]
    todo kb-1 (<TYPEID>)
    Status: in-progress
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Add structured logging

    Use slog library with JSON output.
    [exit 0]
    note kb-2 (<TYPEID>)
    Status: active
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Auth design decisions

    Decided on OAuth2 with PKCE flow.

    Outgoing:
      related-to  kb-0  todo  Implement authentication
    [exit 0]
    kb-2    note  active        Auth design decisions
    kb-1    todo  in-progress   Add structured logging
    [exit 0]
    kb-0    todo  done          Implement authentication
    |}]

let%expect_test "next/claim workflow — dependencies, availability, and progression" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;

    (* Phase 1 — Create todos with dependencies *)
    ignore (Helper.run_bs ~dir ~stdin:"Set up database schema."
      ["add"; "todo"; "Setup database"]);
    ignore (Helper.run_bs ~dir ~stdin:"Build API endpoints."
      ["add"; "todo"; "Build API"]);
    ignore (Helper.run_bs ~dir ~stdin:"Write end-to-end tests."
      ["add"; "todo"; "Write tests"]);
    (* kb-1 (Build API) depends on kb-0 (Setup database) *)
    ignore (Helper.run_bs ~dir ["relate"; "kb-1"; "--depends-on"; "kb-0"; "--blocking"]);
    (* kb-2 (Write tests) depends on kb-1 (Build API) *)
    ignore (Helper.run_bs ~dir ["relate"; "kb-2"; "--depends-on"; "kb-1"; "--blocking"]);

    (* Phase 2 — List available: only kb-0 is unblocked *)
    let avail1 = Helper.run_bs ~dir ["list"; "--available"] in
    Helper.print_result ~dir avail1;

    (* Phase 3 — next claims kb-0 *)
    let next1 = Helper.run_bs ~dir ["next"] in
    Helper.print_result ~dir next1;

    (* Phase 4 — Show kb-0 is in-progress *)
    let show0 = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show0;

    (* Phase 5 — Resolve kb-0, next picks kb-1 *)
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    let avail2 = Helper.run_bs ~dir ["list"; "--available"] in
    Helper.print_result ~dir avail2;

    let next2 = Helper.run_bs ~dir ["next"] in
    Helper.print_result ~dir next2;

    (* Phase 6 — Claim kb-2 directly fails (blocked) *)
    let claim_blocked = Helper.run_bs ~dir ["claim"; "kb-2"] in
    Helper.print_result ~dir claim_blocked;

    (* Phase 7 — Resolve kb-1, claim kb-2 *)
    ignore (Helper.run_bs ~dir ["resolve"; "kb-1"]);
    let claim2 = Helper.run_bs ~dir ["claim"; "kb-2"] in
    Helper.print_result ~dir claim2;

    (* Phase 8 — Resolve kb-2, next returns nothing *)
    ignore (Helper.run_bs ~dir ["resolve"; "kb-2"]);
    let next_empty = Helper.run_bs ~dir ["next"] in
    Helper.print_result ~dir next_empty);
  [%expect {|
    [exit 0]
    kb-0    todo  open          Setup database
    [exit 0]
    Claimed todo: kb-0  Setup database
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Setup database

    Set up database schema.

    Incoming:
      depends-on  kb-1  todo  Build API  [blocking]
    [exit 0]
    kb-1    todo  open          Build API
    [exit 0]
    Claimed todo: kb-1  Build API
    [exit 1]
    STDERR: Error: kb-2 is blocked by kb-1
    [exit 0]
    Claimed todo: kb-2  Write tests
    [exit 0]
    No open unblocked todos
    |}]

let%expect_test "cleanup workflow — reopen, unrelate, delete, and gc" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;

    (* Phase 1 — Seed items and relations *)
    ignore (Helper.run_bs ~dir ~stdin:"Main task body."
      ["add"; "todo"; "Main task"]);
    ignore (Helper.run_bs ~dir ~stdin:"Supporting research."
      ["add"; "note"; "Research notes"]);
    ignore (Helper.run_bs ~dir ~stdin:"Sub-task body."
      ["add"; "todo"; "Sub-task"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--depends-on"; "kb-2"]);
    ignore (Helper.run_bs ~dir ["relate"; "kb-0"; "--related-to"; "kb-1"]);

    (* Phase 2 — Resolve and archive *)
    ignore (Helper.run_bs ~dir ["resolve"; "kb-2"]);
    ignore (Helper.run_bs ~dir ["resolve"; "kb-0"]);
    ignore (Helper.run_bs ~dir ["archive"; "kb-1"]);

    (* Phase 3 — Reopen: requirements changed *)
    let reopen = Helper.run_bs ~dir ["reopen"; "kb-0"] in
    Helper.print_result ~dir reopen;
    let show_kb0 = Helper.run_bs ~dir ["show"; "kb-0"] in
    Helper.print_result ~dir show_kb0;

    (* Phase 4 — Unrelate: dependency no longer relevant *)
    let unrelate = Helper.run_bs ~dir ["unrelate"; "kb-0"; "--depends-on"; "kb-2"] in
    Helper.print_result ~dir unrelate;

    (* Phase 5 — Delete the obsolete sub-task *)
    let delete = Helper.run_bs ~dir ["delete"; "kb-2"] in
    Helper.print_result ~dir delete;

    (* Phase 6 — GC (nothing old enough, but exercises the command) *)
    let gc = Helper.run_bs ~dir ["gc"] in
    Helper.print_result ~dir gc;

    let list_final = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list_final);
  [%expect {|
    [exit 0]
    Reopened todo: kb-0
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Main task

    Main task body.

    Outgoing:
      related-to  kb-1  note  Research notes
      depends-on  kb-2  todo  Sub-task
    [exit 0]
    Unrelated: kb-0 depends-on kb-2 (removed)
    [exit 0]
    Deleted todo: kb-2
    [exit 0]
    GC: removed 0 item(s), 0 relation(s).
    [exit 0]
    kb-0    todo  open          Main task
    |}]
