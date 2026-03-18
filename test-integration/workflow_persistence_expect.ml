module Helper = Test_helper

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
    kb-2    todo  open          Second task
    kb-1    note  active        Design doc
    kb-0    todo  in-progress   First task
    [exit 0]
    todo kb-0 (<TYPEID>)
    Status: in-progress
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  First task

    Implement the first task.

    Outgoing:
      depends-on  kb-2  todo  Second task  [blocking]
    [exit 0]
    todo kb-2 (<TYPEID>)
    Status: open
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Second task

    Implement the second task.

    Outgoing:
      related-to  kb-1  note  Design doc

    Incoming:
      depends-on  kb-0  todo  First task  [blocking]
    [exit 0]
    Rebuilt SQLite from .kbases.jsonl
    [exit 0]
    kb-2    todo  open          Second task
    kb-1    todo  in-progress   First task
    kb-0    note  active        Design doc
    [exit 0]
    todo kb-1 (<TYPEID>)
    Status: in-progress
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  First task

    Implement the first task.

    Outgoing:
      depends-on  kb-2  todo  Second task  [blocking]
    [exit 0]
    kb-2    todo  open          Second task
    kb-0    note  active        Design doc
    |}]

let%expect_test "auto-rebuild — create items with relations, delete db, verify recovery" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Design notes for the feature."
      ["add"; "note"; "Design doc"]);
    ignore (Helper.run_bs ~dir ~stdin:"Implement the feature."
      ["add"; "todo"; "Implementation"]);
    ignore (Helper.run_bs ~dir
      ["relate"; "kb-1"; "--related-to"; "kb-0"]);
    ignore (Helper.run_bs ~dir
      ["update"; "kb-1"; "--status"; "in-progress"]);
    Helper.delete_db dir;
    let list_result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list_result;
    let show_result = Helper.run_bs ~dir ["show"; "kb-1"] in
    Helper.print_result ~dir show_result;
    ignore (Helper.run_bs ~dir ["resolve"; "kb-1"]);
    let show_resolved = Helper.run_bs ~dir ["show"; "kb-1"] in
    Helper.print_result ~dir show_resolved);
  [%expect {|
    [exit 0]
    kb-1    todo  in-progress   Implementation
    kb-0    note  active        Design doc
    [exit 0]
    todo kb-1 (<TYPEID>)
    Status: in-progress
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Implementation

    Implement the feature.

    Outgoing:
      related-to  kb-0  note  Design doc
    [exit 0]
    todo kb-1 (<TYPEID>)
    Status: done
    Created: <TIMESTAMP>
    Updated: <TIMESTAMP>
    Title:  Implementation

    Implement the feature.

    Outgoing:
      related-to  kb-0  note  Design doc
    |}]
