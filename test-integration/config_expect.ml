module Helper = Test_helper

(* --- config list --- *)

let%expect_test "bs config list shows all keys after fresh init" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["config"; "list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    namespace     kb
    gc_max_age    2592000
    mode          shared
  |}]

let%expect_test "bs config list --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["config"; "list"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    let entries = Helper.get_list json "entries" in
    List.iter (fun e ->
      Printf.printf "%s=%s\n"
        (Helper.get_string e "key") (Helper.get_string e "value")
    ) entries);
  [%expect {|
    [exit 0]
    ok: true
    namespace=kb
    gc_max_age=2592000
    mode=shared
  |}]

(* --- config get --- *)

let%expect_test "bs config get namespace" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["config"; "get"; "namespace"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    kb
  |}]

let%expect_test "bs config get gc_max_age shows default" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["config"; "get"; "gc_max_age"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    2592000
  |}]

let%expect_test "bs config get gc_max_age --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["config"; "get"; "gc_max_age"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "key: %s\n" (Helper.get_string json "key");
    Printf.printf "value: %s\n" (Helper.get_string json "value"));
  [%expect {|
    [exit 0]
    ok: true
    key: gc_max_age
    value: 2592000
  |}]

let%expect_test "bs config get dirty returns error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["config"; "get"; "dirty"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: unknown config key: dirty
  |}]

let%expect_test "bs config get nonexistent returns error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["config"; "get"; "nonexistent"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: unknown config key: nonexistent
  |}]

(* --- config set --- *)

let%expect_test "bs config set gc_max_age then get confirms" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let set_result = Helper.run_bs ~dir
      ["config"; "set"; "gc_max_age"; "604800"] in
    Helper.print_result ~dir set_result;
    let get_result = Helper.run_bs ~dir ["config"; "get"; "gc_max_age"] in
    Helper.print_result ~dir get_result);
  [%expect {|
    [exit 0]
    gc_max_age set to: 604800
    [exit 0]
    604800
  |}]

let%expect_test "bs config set gc_max_age banana returns error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir
      ["config"; "set"; "gc_max_age"; "banana"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: invalid gc_max_age: "banana" (expected integer seconds)
  |}]

let%expect_test "bs config set gc_max_age 7d returns error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir
      ["config"; "set"; "gc_max_age"; "7d"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: invalid gc_max_age: "7d" (expected integer seconds)
  |}]

let%expect_test "bs config set mode shared when already shared returns error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir
      ["config"; "set"; "mode"; "shared"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: nothing to update
  |}]

let%expect_test "bs config set mode local succeeds and get confirms" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let set_result = Helper.run_bs ~dir
      ["config"; "set"; "mode"; "local"] in
    Helper.print_result ~dir set_result;
    let get_result = Helper.run_bs ~dir ["config"; "get"; "mode"] in
    Helper.print_result ~dir get_result);
  [%expect {|
    [exit 0]
    mode set to: local
    [exit 0]
    local
  |}]

(* --- namespace rename --- *)

let%expect_test "namespace rename updates niceids in bs list" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body"
      ["add"; "todo"; "Task"]);
    ignore (Helper.run_bs ~dir ~stdin:"Notes"
      ["add"; "note"; "A note"]);
    let set_result = Helper.run_bs ~dir
      ["config"; "set"; "namespace"; "proj"] in
    Helper.print_result ~dir set_result;
    let list_result = Helper.run_bs ~dir ["list"] in
    Helper.print_result ~dir list_result);
  [%expect {|
    [exit 0]
    namespace set to: proj
    [exit 0]
    proj-1  note  active        A note
    proj-0  todo  open          Task
  |}]

let%expect_test "bs config set namespace UPPER returns validation error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir
      ["config"; "set"; "namespace"; "UPPER"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: namespace must match `^[a-z]+$`, got "UPPER"
  |}]

(* --- mode change local to shared --- *)

let%expect_test "mode change local to shared creates JSONL" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir
      ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "local"]);
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    let set_result = Helper.run_bs ~dir
      ["config"; "set"; "mode"; "shared"] in
    Helper.print_result ~dir set_result;
    let jsonl_exists =
      Sys.file_exists (Filename.concat dir ".kbases.jsonl")
    in
    Printf.printf "jsonl exists: %b\n" jsonl_exists);
  [%expect {|
    [exit 0]
    mode set to: shared
    jsonl exists: true
  |}]

let%expect_test "bs config set gc_max_age --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir
      ["config"; "set"; "gc_max_age"; "604800"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok"));
  [%expect {|
    [exit 0]
    ok: true
  |}]

(* --- auto-rebuild --- *)

let%expect_test "bs config list auto-rebuilds when db is missing" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ~stdin:"Body" ["add"; "todo"; "Task"]);
    Helper.delete_db dir;
    let result = Helper.run_bs ~dir ["config"; "list"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    namespace     kb
    gc_max_age    2592000
    mode          shared
  |}]

(* --- JSON errors --- *)

let%expect_test "bs config get dirty --json returns JSON error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir
      ["config"; "get"; "dirty"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "message: %s\n" (Helper.get_string json "message"));
  [%expect {|
    [exit 1]
    ok: false
    message: unknown config key: dirty
  |}]
