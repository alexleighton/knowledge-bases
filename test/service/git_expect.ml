module Git = Kbases.Service.Git

open Test_helpers

let%expect_test "find_repo_root with explicit start_dir" =
  with_git_root "kb-git-test-" (fun root ->
    let child = Filename.concat root "child" in
    let grandchild = Filename.concat child "grandchild" in
    Unix.mkdir child 0o755;
    Unix.mkdir grandchild 0o755;
    (match Git.find_repo_root ~start_dir:grandchild () with
    | Some path ->
      Printf.printf "root match = %b\n"
        (normalize path = normalize root)
    | None -> print_endline "none"));
  [%expect {|
    root match = true
  |}]

let%expect_test "is_git_root checks exact directory only" =
  with_git_root "kb-git-test-" (fun root ->
    let child = Filename.concat root "child" in
    Unix.mkdir child 0o755;
    Printf.printf "root: %b\n" (Git.is_git_root root);
    Printf.printf "child: %b\n" (Git.is_git_root child));
  [%expect {|
    root: true
    child: false
  |}]

let%expect_test "find_repo_root defaults to cwd" =
  with_git_root "kb-git-test-" (fun root ->
    let nested = Filename.concat root "nested" in
    Unix.mkdir nested 0o755;
    with_chdir nested (fun () ->
      match Git.find_repo_root () with
      | Some path ->
        Printf.printf "cwd root match = %b\n"
          (normalize path = normalize root)
      | None -> print_endline "none"));
  [%expect {|
    cwd root match = true
  |}]

let%expect_test "find_repo_root returns None when no git" =
  with_temp_dir "kb-git-no-" (fun dir ->
    match Git.find_repo_root ~start_dir:dir () with
    | Some _ -> print_endline "some"
    | None -> print_endline "none");
  [%expect {|
    none
  |}]

let%expect_test "repo_name strips trailing separator" =
  Printf.printf "%s\n" (Git.repo_name "/tmp/example/");
  [%expect {|
    example
  |}]

let%expect_test "repo_name simple path" =
  Printf.printf "%s\n" (Git.repo_name "/tmp/another");
  [%expect {|
    another
  |}]

(* --- add_exclude --- *)

module Io = Kbases.Control.Io

let exclude_path root =
  Filename.concat (Filename.concat (Filename.concat root ".git") "info") "exclude"

let pp_add = function
  | Git.Added -> "Added"
  | Git.Already_present -> "Already_present"

let pp_remove = function
  | Git.Removed -> "Removed"
  | Git.Remove_not_found -> "Remove_not_found"

let%expect_test "add_exclude creates info dir and file when absent" =
  with_git_root "kb-git-excl-" (fun root ->
    let result = Git.add_exclude ~directory:root ".kbases.db" in
    Printf.printf "result: %s\n" (pp_add result);
    let contents = Io.read_file (exclude_path root) in
    Printf.printf "contents: %S\n" contents);
  [%expect {|
    result: Added
    contents: ".kbases.db\n"
  |}]

let%expect_test "add_exclude appends to existing file" =
  with_git_root "kb-git-excl-" (fun root ->
    let info_dir = Filename.concat (Filename.concat root ".git") "info" in
    Unix.mkdir info_dir 0o755;
    Io.write_file ~path:(exclude_path root) ~contents:"*.log\n";
    let result = Git.add_exclude ~directory:root ".kbases.db" in
    Printf.printf "result: %s\n" (pp_add result);
    let contents = Io.read_file (exclude_path root) in
    Printf.printf "contents: %S\n" contents);
  [%expect {|
    result: Added
    contents: "*.log\n.kbases.db\n"
  |}]

let%expect_test "add_exclude returns Already_present when entry exists" =
  with_git_root "kb-git-excl-" (fun root ->
    let info_dir = Filename.concat (Filename.concat root ".git") "info" in
    Unix.mkdir info_dir 0o755;
    Io.write_file ~path:(exclude_path root) ~contents:".kbases.db\n";
    let result = Git.add_exclude ~directory:root ".kbases.db" in
    Printf.printf "result: %s\n" (pp_add result));
  [%expect {|
    result: Already_present
  |}]

(* --- remove_exclude --- *)

let%expect_test "remove_exclude removes entry from among others" =
  with_git_root "kb-git-excl-" (fun root ->
    let info_dir = Filename.concat (Filename.concat root ".git") "info" in
    Unix.mkdir info_dir 0o755;
    Io.write_file ~path:(exclude_path root) ~contents:"*.log\n.kbases.db\n*.tmp\n";
    let result = Git.remove_exclude ~directory:root ".kbases.db" in
    Printf.printf "result: %s\n" (pp_remove result);
    let contents = Io.read_file (exclude_path root) in
    Printf.printf "contents: %S\n" contents);
  [%expect {|
    result: Removed
    contents: "*.log\n*.tmp\n"
  |}]

let%expect_test "remove_exclude returns Remove_not_found when file missing" =
  with_git_root "kb-git-excl-" (fun root ->
    let result = Git.remove_exclude ~directory:root ".kbases.db" in
    Printf.printf "result: %s\n" (pp_remove result));
  [%expect {|
    result: Remove_not_found
  |}]

let%expect_test "remove_exclude returns Remove_not_found when entry absent" =
  with_git_root "kb-git-excl-" (fun root ->
    let info_dir = Filename.concat (Filename.concat root ".git") "info" in
    Unix.mkdir info_dir 0o755;
    Io.write_file ~path:(exclude_path root) ~contents:"*.log\n*.tmp\n";
    let result = Git.remove_exclude ~directory:root ".kbases.db" in
    Printf.printf "result: %s\n" (pp_remove result));
  [%expect {|
    result: Remove_not_found
  |}]

let%expect_test "remove_exclude does not match substring of another entry" =
  with_git_root "kb-git-excl-" (fun root ->
    let info_dir = Filename.concat (Filename.concat root ".git") "info" in
    Unix.mkdir info_dir 0o755;
    Io.write_file ~path:(exclude_path root) ~contents:".kbases.db-backup\n";
    let result = Git.remove_exclude ~directory:root ".kbases.db" in
    Printf.printf "result: %s\n" (pp_remove result);
    let contents = Io.read_file (exclude_path root) in
    Printf.printf "contents: %S\n" contents);
  [%expect {|
    result: Remove_not_found
    contents: ".kbases.db-backup\n"
  |}]

let%expect_test "add_exclude then remove_exclude roundtrip" =
  with_git_root "kb-git-excl-" (fun root ->
    let info_dir = Filename.concat (Filename.concat root ".git") "info" in
    Unix.mkdir info_dir 0o755;
    Io.write_file ~path:(exclude_path root) ~contents:"*.log\n";
    ignore (Git.add_exclude ~directory:root ".kbases.db");
    let contents_after_add = Io.read_file (exclude_path root) in
    Printf.printf "after add: %S\n" contents_after_add;
    ignore (Git.remove_exclude ~directory:root ".kbases.db");
    let contents_after_remove = Io.read_file (exclude_path root) in
    Printf.printf "after remove: %S\n" contents_after_remove);
  [%expect {|
    after add: "*.log\n.kbases.db\n"
    after remove: "*.log\n"
  |}]
