module Git = Kbases.Service.Git

let create_repo () =
  let root = Filename.temp_dir "kb-git-test-" "" in
  let git_dir = Filename.concat root ".git" in
  Unix.mkdir git_dir 0o755;
  root

let normalize path =
  try Unix.realpath path with
  | Unix.Unix_error _ -> path

let%expect_test "find_repo_root with explicit start_dir" =
  let root = create_repo () in
  let child = Filename.concat root "child" in
  let grandchild = Filename.concat child "grandchild" in
  Unix.mkdir child 0o755;
  Unix.mkdir grandchild 0o755;
  (match Git.find_repo_root ~start_dir:grandchild () with
  | Some path ->
    Printf.printf "root match = %b\n"
      (normalize path = normalize root)
  | None -> print_endline "none");
  [%expect {|
    root match = true
  |}]

let%expect_test "is_git_root checks exact directory only" =
  let root = create_repo () in
  let child = Filename.concat root "child" in
  Unix.mkdir child 0o755;
  Printf.printf "root: %b\n" (Git.is_git_root root);
  Printf.printf "child: %b\n" (Git.is_git_root child);
  [%expect {|
    root: true
    child: false
  |}]

let%expect_test "find_repo_root defaults to cwd" =
  let root = create_repo () in
  let nested = Filename.concat root "nested" in
  Unix.mkdir nested 0o755;
  let original = Sys.getcwd () in
  Sys.chdir nested;
  (match Git.find_repo_root () with
  | Some path ->
    Printf.printf "cwd root match = %b\n"
      (normalize path = normalize root)
  | None -> print_endline "none");
  Sys.chdir original;
  [%expect {|
    cwd root match = true
  |}]

let%expect_test "find_repo_root returns None when no git" =
  let dir = Filename.temp_dir "kb-git-no-" "" in
  (match Git.find_repo_root ~start_dir:dir () with
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
