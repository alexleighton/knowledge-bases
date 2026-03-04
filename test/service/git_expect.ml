module Git = Kbases.Service.Git

let with_git_root = Test_helpers.with_git_root
let with_temp_dir = Test_helpers.with_temp_dir
let normalize = Test_helpers.normalize
let with_chdir = Test_helpers.with_chdir

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
