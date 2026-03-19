module Lifecycle = Kbases.Service.Lifecycle
module Io = Kbases.Control.Io

let with_git_root = Test_helpers.with_git_root
let with_temp_dir = Test_helpers.with_temp_dir
let normalize = Test_helpers.normalize
let with_chdir = Test_helpers.with_chdir

let pp_error err =
  match err with
  | Lifecycle.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | Lifecycle.Validation_error msg -> Printf.printf "validation error: %s\n" msg

let expect_ok result f =
  match result with
  | Error err -> pp_error err
  | Ok v -> f v

(* --- uninstall_file --- *)

let%expect_test "uninstall_file deletes an existing file" =
  with_temp_dir "lc-uninstall-file-exists-" (fun dir ->
    let path = Filename.concat dir "test.db" in
    Io.write_file ~path ~contents:"data";
    let result = Lifecycle.uninstall_file path in
    Printf.printf "result: %s\n"
      (match result with Lifecycle.Deleted -> "Deleted" | Not_found -> "Not_found");
    Printf.printf "file exists after: %b\n" (Sys.file_exists path));
  [%expect {|
    result: Deleted
    file exists after: false
  |}]

let%expect_test "uninstall_file returns Not_found for missing file" =
  with_temp_dir "lc-uninstall-file-missing-" (fun dir ->
    let path = Filename.concat dir "nonexistent.db" in
    let result = Lifecycle.uninstall_file path in
    Printf.printf "result: %s\n"
      (match result with Lifecycle.Deleted -> "Deleted" | Not_found -> "Not_found"));
  [%expect {|
    result: Not_found
  |}]

(* --- uninstall_git_exclude --- *)

let pp_git_exclude_uninstall = function
  | Lifecycle.Entry_removed -> "Entry_removed"
  | Lifecycle.Entry_not_found -> "Entry_not_found"

let%expect_test "uninstall_git_exclude removes entry from exclude file" =
  with_git_root "lc-ungitex-present-" (fun root ->
    let info_dir = Filename.concat (Filename.concat root ".git") "info" in
    Unix.mkdir info_dir 0o755;
    let exclude_path = Filename.concat info_dir "exclude" in
    Io.write_file ~path:exclude_path ~contents:"*.log\n.kbases.db\n*.tmp\n";
    let result = Lifecycle.uninstall_git_exclude ~directory:root in
    Printf.printf "result: %s\n" (pp_git_exclude_uninstall result);
    let contents = Io.read_file exclude_path in
    Printf.printf "contents: %S\n" contents);
  [%expect {|
    result: Entry_removed
    contents: "*.log\n*.tmp\n"
  |}]

let%expect_test "uninstall_git_exclude returns Entry_not_found when entry absent" =
  with_git_root "lc-ungitex-absent-" (fun root ->
    let info_dir = Filename.concat (Filename.concat root ".git") "info" in
    Unix.mkdir info_dir 0o755;
    let exclude_path = Filename.concat info_dir "exclude" in
    Io.write_file ~path:exclude_path ~contents:"*.log\n*.tmp\n";
    let result = Lifecycle.uninstall_git_exclude ~directory:root in
    Printf.printf "result: %s\n" (pp_git_exclude_uninstall result));
  [%expect {|
    result: Entry_not_found
  |}]

let%expect_test "uninstall_git_exclude returns Entry_not_found when file missing" =
  with_git_root "lc-ungitex-nofile-" (fun root ->
    let result = Lifecycle.uninstall_git_exclude ~directory:root in
    Printf.printf "result: %s\n" (pp_git_exclude_uninstall result));
  [%expect {|
    result: Entry_not_found
  |}]

let%expect_test "uninstall_git_exclude roundtrip with install_git_exclude" =
  with_git_root "lc-ungitex-roundtrip-" (fun root ->
    ignore (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb") ~gc_max_age:None);
    let info_dir = Filename.concat (Filename.concat root ".git") "info" in
    let exclude_path = Filename.concat info_dir "exclude" in
    Printf.printf "entry present before: %b\n"
      (let c = Io.read_file exclude_path in
       Kbases.Data.String.contains_substring ~needle:".kbases.db" c);
    let result = Lifecycle.uninstall_git_exclude ~directory:root in
    Printf.printf "result: %s\n" (pp_git_exclude_uninstall result);
    let contents = Io.read_file exclude_path in
    Printf.printf "entry present after: %b\n"
      (Kbases.Data.String.contains_substring ~needle:".kbases.db" contents));
  [%expect {|
    entry present before: true
    result: Entry_removed
    entry present after: false
  |}]

(* --- uninstall_agents_md --- *)

let pp_agents_md_uninstall = function
  | Lifecycle.File_deleted -> "File_deleted"
  | Lifecycle.Section_removed -> "Section_removed"
  | Lifecycle.Section_modified -> "Section_modified"
  | Lifecycle.Not_found -> "Not_found"

let%expect_test "uninstall_agents_md returns Not_found when file missing" =
  with_temp_dir "lc-unagents-nofile-" (fun dir ->
    let result = Lifecycle.uninstall_agents_md ~directory:dir in
    Printf.printf "result: %s\n" (pp_agents_md_uninstall result));
  [%expect {|
    result: Not_found
  |}]

let%expect_test "uninstall_agents_md deletes file when exact match" =
  with_git_root "lc-unagents-exact-" (fun root ->
    ignore (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb") ~gc_max_age:None);
    let path = Filename.concat root "AGENTS.md" in
    let result = Lifecycle.uninstall_agents_md ~directory:root in
    Printf.printf "result: %s\n" (pp_agents_md_uninstall result);
    Printf.printf "file exists: %b\n" (Sys.file_exists path));
  [%expect {|
    result: File_deleted
    file exists: false
  |}]

let%expect_test "uninstall_agents_md removes appended section" =
  with_git_root "lc-unagents-appended-" (fun root ->
    let path = Filename.concat root "AGENTS.md" in
    let other = "# Other\n\nSome content.\n" in
    Io.write_file ~path ~contents:other;
    ignore (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb") ~gc_max_age:None);
    let result = Lifecycle.uninstall_agents_md ~directory:root in
    Printf.printf "result: %s\n" (pp_agents_md_uninstall result);
    let contents = Io.read_file path in
    Printf.printf "contents: %S\n" contents);
  [%expect {|
    result: Section_removed
    contents: "# Other\n\nSome content.\n"
  |}]

let%expect_test "uninstall_agents_md reports Section_modified when heading present but body edited" =
  with_temp_dir "lc-unagents-modified-" (fun dir ->
    let path = Filename.concat dir "AGENTS.md" in
    Io.write_file ~path ~contents:"## Knowledge Base\n\nCustom content here.\n";
    let result = Lifecycle.uninstall_agents_md ~directory:dir in
    Printf.printf "result: %s\n" (pp_agents_md_uninstall result);
    Printf.printf "file exists: %b\n" (Sys.file_exists path));
  [%expect {|
    result: Section_modified
    file exists: true
  |}]

let%expect_test "uninstall_agents_md roundtrip: init then uninstall deletes file" =
  with_git_root "lc-unagents-roundtrip-" (fun root ->
    ignore (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb") ~gc_max_age:None);
    let path = Filename.concat root "AGENTS.md" in
    Printf.printf "file exists before: %b\n" (Sys.file_exists path);
    let result = Lifecycle.uninstall_agents_md ~directory:root in
    Printf.printf "result: %s\n" (pp_agents_md_uninstall result);
    Printf.printf "file exists after: %b\n" (Sys.file_exists path));
  [%expect {|
    file exists before: true
    result: File_deleted
    file exists after: false
  |}]

(* --- uninstall_kb --- *)

let pp_file_action = function
  | Lifecycle.Deleted -> "Deleted" | Lifecycle.Not_found -> "Not_found"

let%expect_test "uninstall_kb full roundtrip after init_kb" =
  with_git_root "lc-uninstall-roundtrip-" (fun root ->
    ignore (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb") ~gc_max_age:None);
    let db = Filename.concat root ".kbases.db" in
    let jsonl = Filename.concat root ".kbases.jsonl" in
    Printf.printf "db before: %b\n" (Sys.file_exists db);
    Printf.printf "agents before: %b\n" (Sys.file_exists (Filename.concat root "AGENTS.md"));
    expect_ok (Lifecycle.uninstall_kb ~directory:(Some root)) (fun r ->
      Printf.printf "database: %s\n" (pp_file_action r.database);
      Printf.printf "jsonl: %s\n" (pp_file_action r.jsonl);
      Printf.printf "agents_md: %s\n" (pp_agents_md_uninstall r.agents_md);
      Printf.printf "git_exclude: %s\n" (pp_git_exclude_uninstall r.git_exclude);
      Printf.printf "db after: %b\n" (Sys.file_exists db);
      Printf.printf "jsonl after: %b\n" (Sys.file_exists jsonl);
      Printf.printf "agents after: %b\n"
        (Sys.file_exists (Filename.concat root "AGENTS.md"))));
  [%expect {|
    db before: true
    agents before: true
    database: Deleted
    jsonl: Not_found
    agents_md: File_deleted
    git_exclude: Entry_removed
    db after: false
    jsonl after: false
    agents after: false
  |}]

let%expect_test "uninstall_kb on git root with no KB reports not found" =
  with_git_root "lc-uninstall-empty-" (fun root ->
    expect_ok (Lifecycle.uninstall_kb ~directory:(Some root)) (fun r ->
      Printf.printf "database: %s\n" (pp_file_action r.database);
      Printf.printf "jsonl: %s\n" (pp_file_action r.jsonl);
      Printf.printf "agents_md: %s\n" (pp_agents_md_uninstall r.agents_md);
      Printf.printf "git_exclude: %s\n" (pp_git_exclude_uninstall r.git_exclude)));
  [%expect {|
    database: Not_found
    jsonl: Not_found
    agents_md: Not_found
    git_exclude: Entry_not_found
  |}]

let%expect_test "uninstall_kb resolves repo root from cwd when directory is None" =
  with_git_root "lc-uninstall-cwd-" (fun root ->
    ignore (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb") ~gc_max_age:None);
    let nested = Filename.concat root "nested" in
    Unix.mkdir nested 0o755;
    with_chdir nested (fun () ->
      expect_ok (Lifecycle.uninstall_kb ~directory:None) (fun r ->
        Printf.printf "dir resolved: %b\n" (normalize r.directory = normalize root);
        Printf.printf "database: %s\n" (pp_file_action r.database);
        Printf.printf "agents_md: %s\n" (pp_agents_md_uninstall r.agents_md);
        Printf.printf "db exists: %b\n"
          (Sys.file_exists (Filename.concat root ".kbases.db"));
        Printf.printf "agents exists: %b\n"
          (Sys.file_exists (Filename.concat root "AGENTS.md")))));
  [%expect {|
    dir resolved: true
    database: Deleted
    agents_md: File_deleted
    db exists: false
    agents exists: false
  |}]

let%expect_test "uninstall_kb outside git root returns error" =
  with_temp_dir "lc-uninstall-no-git-" (fun dir ->
    with_chdir dir (fun () ->
      match Lifecycle.uninstall_kb ~directory:None with
      | Ok _ -> print_endline "unexpected success"
      | Error err -> pp_error err));
  [%expect {|
    validation error: Not inside a git repository. Use -d to specify a directory.
  |}]
