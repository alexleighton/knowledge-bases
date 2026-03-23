module Helper = Test_helper

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
