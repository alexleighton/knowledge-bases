module Helper = Test_helper
module Root = Kbases.Repository.Root
module Config = Kbases.Repository.Config
module Io = Kbases.Control.Io

let with_root db_file f =
  match Root.init ~db_file ~namespace:None with
  | Error (Root.Backend_failure msg) -> Printf.printf "root open failed: %s\n" msg
  | Ok root ->
      Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f root)

let contains_substring = Kbases.Data.String.contains_substring

let%expect_test "bs init with explicit directory and namespace" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"] in
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

let%expect_test "bs init creates database with correct namespace" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "test"]);
    let db_file = Filename.concat dir ".kbases.db" in
    Printf.printf "db exists: %b\n" (Sys.file_exists db_file);
    let real_db =
      Filename.concat
        (try Unix.realpath dir with Unix.Unix_error _ -> dir)
        ".kbases.db"
    in
    with_root real_db (fun opened ->
      match Config.get (Root.config opened) "namespace" with
      | Ok ns -> Printf.printf "namespace: %s\n" ns
      | Error _ -> print_endline "namespace: not found"));
  [%expect {|
    db exists: true
    namespace: test
  |}]

let%expect_test "bs init resolves git root from cwd" =
  Helper.with_git_root (fun dir ->
    let nested = Filename.concat dir "subdir" in
    Unix.mkdir nested 0o755;
    let result = Helper.run_bs ~dir:nested ["init"; "-n"; "kb"] in
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

let%expect_test "bs init in non-git directory fails" =
  Helper.with_temp_dir ~name:"kb-integ-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Directory is not a git repository root: <DIR>
  |}]

let%expect_test "bs init with invalid namespace fails" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "NOPE"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: namespace must match `^[a-z]+$`, got "NOPE"
  |}]

let%expect_test "bs init refuses re-initialisation" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"]);
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Knowledge base already initialised at <DIR>/.kbases.db.
  |}]

let%expect_test "bs init outside git repo with no args fails" =
  Helper.with_temp_dir ~name:"kb-integ-outside-" (fun dir ->
    let result = Helper.run_bs ~dir ["init"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Use -d to specify a directory.
  |}]

let%expect_test "bs init creates AGENTS.md with expected content" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"]);
    let agents_md_path = Filename.concat dir "AGENTS.md" in
    Printf.printf "AGENTS.md exists: %b\n" (Sys.file_exists agents_md_path);
    let contents = Helper.read_file agents_md_path in
    if contains_substring ~needle:"Knowledge Base" contents
    then print_endline "has section heading: true"
    else Printf.printf "missing 'Knowledge Base' in:\n%s\n" contents;
    if contains_substring ~needle:"bs add todo" contents
    then print_endline "has add todo example: true"
    else Printf.printf "missing 'bs add todo' in:\n%s\n" contents;
    if contains_substring ~needle:"bs --help" contents
    then print_endline "has --help pointer: true"
    else Printf.printf "missing 'bs --help' in:\n%s\n" contents);
  [%expect {|
    AGENTS.md exists: true
    has section heading: true
    has add todo example: true
    has --help pointer: true
  |}]

let%expect_test "bs init appends to existing AGENTS.md" =
  Helper.with_git_root (fun dir ->
    let agents_md_path = Filename.concat dir "AGENTS.md" in
    Io.write_file ~path:agents_md_path
      ~contents:"# Project\n\nExisting agent instructions.\n";
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"] in
    Helper.print_result ~dir result;
    let contents = Helper.read_file agents_md_path in
    if contains_substring ~needle:"Existing agent instructions." contents
    then print_endline "has original content: true"
    else Printf.printf "missing original content in:\n%s\n" contents;
    if contains_substring ~needle:"Knowledge Base" contents
    then print_endline "has kbases section: true"
    else Printf.printf "missing 'Knowledge Base' in:\n%s\n" contents);
  [%expect {|
    [exit 0]
    Initialised knowledge base:
      Directory:   <DIR>
      Namespace:   kb
      Database:    <DIR>/.kbases.db
      Mode:        shared
      AGENTS.md:   appended to existing file
      Git exclude: added to .git/info/exclude
      GC max age:  2592000 (default)
    has original content: true
    has kbases section: true
    |}]

let%expect_test "bs init is idempotent when AGENTS.md section already present" =
  Helper.with_git_root (fun dir ->
    let agents_md_path = Filename.concat dir "AGENTS.md" in
    Io.write_file ~path:agents_md_path
      ~contents:"# Project\n\n## ※ Knowledge Base\n\nExisting section.\n";
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"] in
    Helper.print_result ~dir result;
    let contents = Helper.read_file agents_md_path in
    let count_occurrences needle haystack =
      let nlen = String.length needle and hlen = String.length haystack in
      let count = ref 0 in
      for i = 0 to hlen - nlen do
        if String.sub haystack i nlen = needle then incr count
      done;
      !count
    in
    Printf.printf "heading count: %d\n"
      (count_occurrences "Knowledge Base" contents));
  [%expect {|
    [exit 0]
    Initialised knowledge base:
      Directory:   <DIR>
      Namespace:   kb
      Database:    <DIR>/.kbases.db
      Mode:        shared
      AGENTS.md:   section already present
      Git exclude: added to .git/info/exclude
      GC max age:  2592000 (default)
    heading count: 1
    |}]

let%expect_test "bs init creates .git/info/exclude with .kbases.db" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"]);
    let exclude_path =
      Filename.concat (Filename.concat (Filename.concat dir ".git") "info") "exclude"
    in
    Printf.printf "exclude exists: %b\n" (Sys.file_exists exclude_path);
    let contents = Helper.read_file exclude_path in
    if contains_substring ~needle:".kbases.db" contents
    then print_endline "has .kbases.db: true"
    else Printf.printf "missing '.kbases.db' in:\n%s\n" contents);
  [%expect {|
    exclude exists: true
    has .kbases.db: true
  |}]

let%expect_test "bs init preserves existing .git/info/exclude content" =
  Helper.with_git_root (fun dir ->
    let info_dir = Filename.concat (Filename.concat dir ".git") "info" in
    Unix.mkdir info_dir 0o755;
    let exclude_path = Filename.concat info_dir "exclude" in
    Io.write_file ~path:exclude_path ~contents:"*.swp\n.DS_Store\n";
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"]);
    let contents = Helper.read_file exclude_path in
    if contains_substring ~needle:"*.swp" contents
    then print_endline "has original: true"
    else Printf.printf "missing '*.swp' in:\n%s\n" contents;
    if contains_substring ~needle:".kbases.db" contents
    then print_endline "has .kbases.db: true"
    else Printf.printf "missing '.kbases.db' in:\n%s\n" contents);
  [%expect {|
    has original: true
    has .kbases.db: true
  |}]

let%expect_test "bs init --gc-max-age persists the setting" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--gc-max-age"; "1209600"] in
    Helper.print_result ~dir result;
    let show = Helper.run_bs ~dir ["config"; "get"; "gc_max_age"] in
    Helper.print_result ~dir show);
  [%expect {|
    [exit 0]
    Initialised knowledge base:
      Directory:   <DIR>
      Namespace:   kb
      Database:    <DIR>/.kbases.db
      Mode:        shared
      AGENTS.md:   created
      Git exclude: added to .git/info/exclude
      GC max age:  1209600
    [exit 0]
    1209600
    |}]

let%expect_test "bs init --json returns ok with directory and db_file" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "has directory: %b\n" (Helper.get_string json "directory" <> "<missing>");
    Printf.printf "namespace: %s\n" (Helper.get_string json "namespace");
    Printf.printf "has db_file: %b\n" (Helper.get_string json "db_file" <> "<missing>");
    Printf.printf "mode: %s\n" (Helper.get_string json "mode");
    Printf.printf "agents_md: %s\n" (Helper.get_string json "agents_md");
    Printf.printf "git_exclude: %s\n" (Helper.get_string json "git_exclude"));
  [%expect {|
    [exit 0]
    ok: true
    has directory: true
    namespace: kb
    has db_file: true
    mode: shared
    agents_md: created
    git_exclude: added to .git/info/exclude
  |}]

