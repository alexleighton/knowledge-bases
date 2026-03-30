module Helper = Test_helper

let%expect_test "bs init --mode local" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "local"] in
    Helper.print_result ~dir result;
    Printf.printf "jsonl exists: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.jsonl")));
  [%expect {|
    [exit 0]
    Initialised knowledge base:
      Directory:   <DIR>
      Namespace:   kb
      Database:    <DIR>/.kbases.db
      Mode:        local
      AGENTS.md:   created
      Git exclude: added to .git/info/exclude
      GC max age:  2592000 (default)
    jsonl exists: false
  |}]

let%expect_test "bs init --mode shared" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "shared"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Initialised knowledge base:
      Directory:   <DIR>
      Namespace:   kb
      Database:    <DIR>/.kbases.db
      Mode:        shared
      AGENTS.md:   created
      Git exclude: added to .git/info/exclude
      GC max age:  2592000 (default)
  |}]

let%expect_test "bs init --mode foo rejects invalid mode" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "foo"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    Printf.printf "has error: %b\n"
      (Kbases.Data.String.contains_substring ~needle:"invalid" result.stderr
       || Kbases.Data.String.contains_substring ~needle:"invalid" result.stdout));
  [%expect {|
    [exit 124]
    has error: true
  |}]

let%expect_test "bs init --mode local --json" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--mode"; "local"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "mode: %s\n" (Helper.get_string json "mode"));
  [%expect {|
    [exit 0]
    ok: true
    mode: local
  |}]
