module Root = Kbases.Repository.Root
module Config = Kbases.Repository.Config
module Lifecycle = Kbases.Service.Lifecycle

let create_git_root = Test_helpers.create_git_root
let starts_with = Test_helpers.starts_with
let normalize = Test_helpers.normalize
let with_chdir = Test_helpers.with_chdir
let with_root = Test_helpers.with_root

let pp_error err =
  match err with
  | Lifecycle.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | Lifecycle.Validation_error msg -> Printf.printf "validation error: %s\n" msg

let expect_ok result f =
  match result with
  | Error err -> pp_error err
  | Ok v -> f v

let%expect_test "init_kb succeeds with explicit directory and namespace" =
  let root = create_git_root "lc-init-explicit-" in
  expect_ok (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb")) (fun result ->
    Printf.printf "db exists: %b\n" (Sys.file_exists result.db_file);
    with_root result.db_file (fun opened ->
      match Config.get (Root.config opened) "namespace" with
      | Ok ns -> Printf.printf "namespace persisted: %b\n" (ns = "kb")
      | Error _ -> print_endline "namespace persisted: false"));
  [%expect {|
    db exists: true
    namespace persisted: true
  |}]

let%expect_test "init_kb rejects non-git root directory" =
  let dir = Filename.temp_dir "lc-init-not-git-" "" in
  match Lifecycle.init_kb ~directory:(Some dir) ~namespace:(Some "kb") with
  | Ok _ -> print_endline "unexpected success"
  | Error (Lifecycle.Repository_error msg) ->
      Printf.printf "repo error: %s\n" msg
  | Error (Lifecycle.Validation_error msg) ->
      Printf.printf "is-dir-error: %b\n"
        (starts_with msg "Directory is not a git repository root: ");
  [%expect {|
    is-dir-error: true
  |}]

let%expect_test "init_kb rejects invalid explicit namespace" =
  let root = create_git_root "lc-init-invalid-ns-" in
  match Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "TooLong") with
  | Ok _ -> print_endline "unexpected success"
  | Error (Lifecycle.Repository_error msg) ->
      Printf.printf "repo error: %s\n" msg
  | Error (Lifecycle.Validation_error msg) ->
      Printf.printf "%s\n" msg;
  [%expect {|
    namespace must be between 1 and 5 characters, got "TooLong"
  |}]

let%expect_test "init_kb guards against re-initialization" =
  let root = create_git_root "lc-init-reinit-" in
  ignore (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb"));
  match Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb") with
  | Ok _ -> print_endline "unexpected success"
  | Error (Lifecycle.Repository_error msg) ->
      Printf.printf "repo error: %s\n" msg
  | Error (Lifecycle.Validation_error msg) ->
      Printf.printf "already-init-error: %b\n"
        (starts_with msg "Knowledge base already initialised at ");
  [%expect {|
    already-init-error: true
  |}]

let%expect_test "init_kb resolves repo root from cwd when directory is None" =
  let root = create_git_root "lc-init-no-args-" in
  let nested = Filename.concat root "nested" in
  Unix.mkdir nested 0o755;
  with_chdir nested (fun () ->
    match Lifecycle.init_kb ~directory:None ~namespace:(Some "kb") with
    | Error err -> pp_error err
    | Ok result ->
        Printf.printf "dir resolved: %b\n"
          (normalize result.directory = normalize root);
        Printf.printf "db exists: %b\n" (Sys.file_exists result.db_file));
  [%expect {|
    dir resolved: true
    db exists: true
  |}]

let%expect_test "init_kb without directory fails outside git repos" =
  let dir = Filename.temp_dir "lc-init-outside-" "" in
  with_chdir dir (fun () ->
    match Lifecycle.init_kb ~directory:None ~namespace:(Some "kb") with
    | Ok _ -> print_endline "unexpected success"
    | Error (Lifecycle.Repository_error msg) -> Printf.printf "repo error: %s\n" msg
    | Error (Lifecycle.Validation_error msg) -> print_endline msg);
  [%expect {|
    Not inside a git repository. Use -d to specify a directory.
  |}]

let%expect_test "init_kb reports invalid derived namespace" =
  let parent = Filename.temp_dir "lc-init-parent-" "" in
  let root = Filename.concat parent "kb-2bad" in
  Unix.mkdir root 0o755;
  Unix.mkdir (Filename.concat root ".git") 0o755;
  let nested = Filename.concat root "nested" in
  Unix.mkdir nested 0o755;
  with_chdir nested (fun () ->
    match Lifecycle.init_kb ~directory:None ~namespace:None with
    | Ok _ -> print_endline "unexpected success"
    | Error (Lifecycle.Repository_error msg) -> Printf.printf "repo error: %s\n" msg
    | Error (Lifecycle.Validation_error msg) ->
        Printf.printf "derived-error: %b\n" (starts_with msg "Derived namespace"));
  [%expect {|
    derived-error: true
  |}]

let%expect_test "open_kb fails when not in a git repo" =
  let dir = Filename.temp_dir "lc-open-no-git-" "" in
  with_chdir dir (fun () ->
    match Lifecycle.open_kb () with
    | Ok _ -> print_endline "unexpected success"
    | Error (Lifecycle.Repository_error msg) ->
        Printf.printf "repo error: %s\n" msg
    | Error (Lifecycle.Validation_error msg) -> print_endline msg);
  [%expect {|
    Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "open_kb fails when KB not initialised" =
  let root = create_git_root "lc-open-no-init-" in
  with_chdir root (fun () ->
    match Lifecycle.open_kb () with
    | Ok _ -> print_endline "unexpected success"
    | Error (Lifecycle.Repository_error msg) ->
        Printf.printf "repo error: %s\n" msg
    | Error (Lifecycle.Validation_error msg) -> print_endline msg);
  [%expect {|
    No knowledge base found. Run 'bs init' first.
  |}]
