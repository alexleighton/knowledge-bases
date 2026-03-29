module Helper = Test_helper
module Io = Kbases.Control.Io

let contains_substring = Kbases.Data.String.contains_substring

let exclude_path dir =
  Filename.concat (Filename.concat (Filename.concat dir ".git") "info") "exclude"

(* Scenario 1: Clean uninstall of fully initialized KB *)
let%expect_test "bs uninstall --yes removes all artifacts" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["uninstall"; "--yes"; "-d"; dir] in
    Helper.print_result ~dir result;
    Printf.printf "db exists: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.db"));
    Printf.printf "agents exists: %b\n"
      (Sys.file_exists (Filename.concat dir "AGENTS.md"));
    let exc = exclude_path dir in
    let has_entry = Sys.file_exists exc &&
      contains_substring ~needle:".kbases.db" (Helper.read_file exc) in
    Printf.printf "exclude has entry: %b\n" has_entry);
  [%expect {|
    [exit 0]
    Uninstalled knowledge base:
      Directory:   <DIR>
      Database:    deleted
      JSONL:       not found
      AGENTS.md:   deleted
      Git exclude: entry removed
    db exists: false
    agents exists: false
    exclude has entry: false
  |}]

(* Scenario 2: Uninstall when AGENTS.md has other content (section removed) *)
let%expect_test "bs uninstall --yes removes appended section from AGENTS.md" =
  Helper.with_git_root (fun dir ->
    let agents_path = Filename.concat dir "AGENTS.md" in
    Io.write_file ~path:agents_path ~contents:"# Project\n\nExisting content.\n";
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["uninstall"; "--yes"; "-d"; dir] in
    Helper.print_result ~dir result;
    Printf.printf "agents exists: %b\n" (Sys.file_exists agents_path);
    let contents = Helper.read_file agents_path in
    Printf.printf "has original: %b\n"
      (contains_substring ~needle:"Existing content." contents);
    Printf.printf "has kb section: %b\n"
      (contains_substring ~needle:"## Knowledge Base" contents));
  [%expect {|
    [exit 0]
    Uninstalled knowledge base:
      Directory:   <DIR>
      Database:    deleted
      JSONL:       not found
      AGENTS.md:   section removed
      Git exclude: entry removed
    agents exists: true
    has original: true
    has kb section: false
  |}]

(* Scenario 3: Partial state — some artifacts missing *)
let%expect_test "bs uninstall --yes handles partial state" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    Sys.remove (Filename.concat dir ".kbases.db");
    let result = Helper.run_bs ~dir ["uninstall"; "--yes"; "-d"; dir] in
    Helper.print_result ~dir result;
    Printf.printf "agents exists: %b\n"
      (Sys.file_exists (Filename.concat dir "AGENTS.md"));
    let exc = exclude_path dir in
    let has_entry = Sys.file_exists exc &&
      contains_substring ~needle:".kbases.db" (Helper.read_file exc) in
    Printf.printf "exclude has entry: %b\n" has_entry);
  [%expect {|
    [exit 0]
    Uninstalled knowledge base:
      Directory:   <DIR>
      Database:    not found
      JSONL:       not found
      AGENTS.md:   deleted
      Git exclude: entry removed
    agents exists: false
    exclude has entry: false
  |}]

(* Scenario 4: Roundtrip — init then uninstall restores original state *)
let%expect_test "bs uninstall --yes roundtrip restores original state" =
  Helper.with_git_root (fun dir ->
    let exclude_dir = Filename.concat (Filename.concat dir ".git") "info" in
    Unix.mkdir exclude_dir 0o755;
    let exclude_path = Filename.concat exclude_dir "exclude" in
    Io.write_file ~path:exclude_path ~contents:"*.log\n";
    Helper.init_kb dir;
    ignore (Helper.run_bs ~dir ["uninstall"; "--yes"; "-d"; dir]);
    Printf.printf "db exists: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.db"));
    Printf.printf "agents exists: %b\n"
      (Sys.file_exists (Filename.concat dir "AGENTS.md"));
    let exclude_contents = Helper.read_file exclude_path in
    Printf.printf "exclude has log: %b\n"
      (contains_substring ~needle:"*.log" exclude_contents);
    Printf.printf "exclude has kbases: %b\n"
      (contains_substring ~needle:".kbases.db" exclude_contents));
  [%expect {|
    db exists: false
    agents exists: false
    exclude has log: true
    exclude has kbases: false
  |}]

(* Scenario 5: AGENTS.md section edited after init (section modified warning) *)
let%expect_test "bs uninstall --yes warns when AGENTS.md section was modified" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let agents_path = Filename.concat dir "AGENTS.md" in
    let custom_content = "## ※ Knowledge Base\n\nCustomized instructions.\n" in
    Io.write_file ~path:agents_path ~contents:custom_content;
    let result = Helper.run_bs ~dir ["uninstall"; "--yes"; "-d"; dir] in
    Helper.print_result ~dir result;
    Printf.printf "agents still exists: %b\n" (Sys.file_exists agents_path);
    let contents = Helper.read_file agents_path in
    Printf.printf "content preserved: %b\n" (contents = custom_content));
  [%expect {|
    [exit 0]
    Uninstalled knowledge base:
      Directory:   <DIR>
      Database:    deleted
      JSONL:       not found
      AGENTS.md:   section modified (manual removal required)
      Git exclude: entry removed
    agents still exists: true
    content preserved: true
  |}]

(* Scenario 6: Bare uninstall without --yes *)
let%expect_test "bs uninstall without --yes fails" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["uninstall"; "-d"; dir] in
    Helper.print_result ~dir result;
    Printf.printf "db still exists: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.db"));
    Printf.printf "agents still exists: %b\n"
      (Sys.file_exists (Filename.concat dir "AGENTS.md"));
    let exc = exclude_path dir in
    let has_entry = Sys.file_exists exc &&
      contains_substring ~needle:".kbases.db" (Helper.read_file exc) in
    Printf.printf "exclude still has entry: %b\n" has_entry);
  [%expect {|
    [exit 1]
    STDERR: Error: Uninstall is destructive and not intended for agent use. Pass --yes to confirm.
    db still exists: true
    agents still exists: true
    exclude still has entry: true
  |}]

(* Scenario 7: Uninstall outside a git repository *)
let%expect_test "bs uninstall --yes outside git repo fails" =
  Helper.with_temp_dir (fun dir ->
    let result = Helper.run_bs ~dir ["uninstall"; "--yes"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Use -d to specify a directory.
  |}]

(* Scenario 8: JSON output *)
let%expect_test "bs uninstall --yes --json" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["uninstall"; "--yes"; "-d"; dir; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "database: %s\n" (Helper.get_string json "database");
    Printf.printf "jsonl: %s\n" (Helper.get_string json "jsonl");
    Printf.printf "agents_md: %s\n" (Helper.get_string json "agents_md");
    Printf.printf "git_exclude: %s\n" (Helper.get_string json "git_exclude");
    Printf.printf "db exists: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.db"));
    Printf.printf "agents exists: %b\n"
      (Sys.file_exists (Filename.concat dir "AGENTS.md"));
    let exc = exclude_path dir in
    let has_entry = Sys.file_exists exc &&
      contains_substring ~needle:".kbases.db" (Helper.read_file exc) in
    Printf.printf "exclude has entry: %b\n" has_entry);
  [%expect {|
    [exit 0]
    ok: true
    database: deleted
    jsonl: not found
    agents_md: deleted
    git_exclude: entry removed
    db exists: false
    agents exists: false
    exclude has entry: false
  |}]

(* Scenario 9: JSON error when --yes omitted *)
let%expect_test "bs uninstall --json without --yes returns JSON error" =
  Helper.with_git_root (fun dir ->
    Helper.init_kb dir;
    let result = Helper.run_bs ~dir ["uninstall"; "-d"; dir; "--json"] in
    Printf.printf "[exit %d]\n" result.exit_code;
    let json = Helper.parse_json result.stdout in
    Printf.printf "ok: %b\n" (Helper.get_bool json "ok");
    Printf.printf "reason: %s\n" (Helper.get_string json "reason");
    Printf.printf "has message: %b\n" (Helper.get_string json "message" <> "<missing>");
    Printf.printf "db still exists: %b\n"
      (Sys.file_exists (Filename.concat dir ".kbases.db")));
  [%expect {|
    [exit 1]
    ok: false
    reason: error
    has message: true
    db still exists: true
  |}]
