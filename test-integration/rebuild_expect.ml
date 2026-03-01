module Helper = Test_helper

let%expect_test "bs rebuild restores entities from JSONL" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Todo body" ["add"; "todo"; "My todo"]);
    ignore (Helper.run_bs ~dir ~stdin:"Note body" ["add"; "note"; "My note"]);

    let result = Helper.run_bs ~dir ["rebuild"] in
    Helper.print_result ~dir result;

    let list_result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list_result);
  [%expect {|
    [exit 0]
    Rebuilt SQLite from .kbases.jsonl
    [exit 0]
    kb-0    note  active        My note
    kb-1    todo  open          My todo
    |}]

let%expect_test "bs rebuild with no JSONL file" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["rebuild"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: JSONL I/O error: <DIR>/.kbases.jsonl: No such file or directory
    |}]

let%expect_test "bs rebuild outside git repo" =
  Helper.with_temp_dir ~name:"kb-rebuild-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["rebuild"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Run 'bs add' from within a git repository.
    |}]

let%expect_test "bs rebuild --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Item"]);
    ignore (Helper.run_bs ~dir ["flush"]);
    let result = Helper.run_bs ~dir ["rebuild"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "action: %s\n" (Helper.get_string json "action");
    Printf.printf "file: %s\n" (Helper.get_string json "file"));
  [%expect {|
    [exit 0]
    ok: true
    action: rebuilt
    file: .kbases.jsonl
  |}]
