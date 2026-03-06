module Root = Kbases.Repository.Root
module Config = Kbases.Repository.Config
module Jsonl = Kbases.Repository.Jsonl
module Lifecycle = Kbases.Service.Lifecycle

let with_git_root = Test_helpers.with_git_root
let with_temp_dir = Test_helpers.with_temp_dir
let normalize = Test_helpers.normalize
let with_chdir = Test_helpers.with_chdir
let with_root = Test_helpers.with_root
let query_count = Test_helpers.query_count

let pp_error err =
  match err with
  | Lifecycle.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | Lifecycle.Validation_error msg -> Printf.printf "validation error: %s\n" msg

let expect_ok result f =
  match result with
  | Error err -> pp_error err
  | Ok v -> f v

let%expect_test "init_kb succeeds with explicit directory and namespace" =
  with_git_root "lc-init-explicit-" (fun root ->
    expect_ok (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb")) (fun result ->
      Printf.printf "db exists: %b\n" (Sys.file_exists result.db_file);
      with_root result.db_file (fun opened ->
        (match Config.get (Root.config opened) "namespace" with
        | Ok ns -> Printf.printf "namespace persisted: %b\n" (ns = "kb")
        | Error _ -> print_endline "namespace persisted: false");
        query_count opened "niceid";
        query_count opened "todo";
        query_count opened "note")));
  [%expect {|
    db exists: true
    namespace persisted: true
    niceid=0
    todo=0
    note=0
  |}]

let%expect_test "init_kb rejects non-git root directory" =
  with_temp_dir "lc-init-not-git-" (fun dir ->
    match Lifecycle.init_kb ~directory:(Some dir) ~namespace:(Some "kb") with
    | Ok _ -> print_endline "unexpected success"
    | Error (Lifecycle.Repository_error msg) ->
        Printf.printf "repo error: %s\n" msg
    | Error (Lifecycle.Validation_error msg) ->
        Printf.printf "is-dir-error: %b\n"
          (String.starts_with ~prefix:"Directory is not a git repository root: " msg));
  [%expect {|
    is-dir-error: true
  |}]

let%expect_test "init_kb rejects invalid explicit namespace" =
  with_git_root "lc-init-invalid-ns-" (fun root ->
    match Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "TooLong") with
    | Ok _ -> print_endline "unexpected success"
    | Error (Lifecycle.Repository_error msg) ->
        Printf.printf "repo error: %s\n" msg
    | Error (Lifecycle.Validation_error msg) ->
        Printf.printf "%s\n" msg);
  [%expect {|
    namespace must be between 1 and 5 characters, got "TooLong"
  |}]

let%expect_test "init_kb guards against re-initialization" =
  with_git_root "lc-init-reinit-" (fun root ->
    ignore (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb"));
    match Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb") with
    | Ok _ -> print_endline "unexpected success"
    | Error (Lifecycle.Repository_error msg) ->
        Printf.printf "repo error: %s\n" msg
    | Error (Lifecycle.Validation_error msg) ->
        Printf.printf "already-init-error: %b\n"
          (String.starts_with ~prefix:"Knowledge base already initialised at " msg));
  [%expect {|
    already-init-error: true
  |}]

let%expect_test "init_kb resolves repo root from cwd when directory is None" =
  with_git_root "lc-init-no-args-" (fun root ->
    let nested = Filename.concat root "nested" in
    Unix.mkdir nested 0o755;
    with_chdir nested (fun () ->
      match Lifecycle.init_kb ~directory:None ~namespace:(Some "kb") with
      | Error err -> pp_error err
      | Ok result ->
          Printf.printf "dir resolved: %b\n"
            (normalize result.directory = normalize root);
          Printf.printf "db exists: %b\n" (Sys.file_exists result.db_file)));
  [%expect {|
    dir resolved: true
    db exists: true
  |}]

let%expect_test "init_kb without directory fails outside git repos" =
  with_temp_dir "lc-init-outside-" (fun dir ->
    with_chdir dir (fun () ->
      match Lifecycle.init_kb ~directory:None ~namespace:(Some "kb") with
      | Ok _ -> print_endline "unexpected success"
      | Error (Lifecycle.Repository_error msg) -> Printf.printf "repo error: %s\n" msg
      | Error (Lifecycle.Validation_error msg) -> print_endline msg));
  [%expect {|
    Not inside a git repository. Use -d to specify a directory.
  |}]

let%expect_test "init_kb reports invalid derived namespace" =
  with_temp_dir "lc-init-parent-" (fun parent ->
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
          Printf.printf "derived-error: %b\n" (String.starts_with ~prefix:"Derived namespace" msg)));
  [%expect {|
    derived-error: true
  |}]

let%expect_test "open_kb fails when not in a git repo" =
  with_temp_dir "lc-open-no-git-" (fun dir ->
    with_chdir dir (fun () ->
      match Lifecycle.open_kb () with
      | Ok _ -> print_endline "unexpected success"
      | Error (Lifecycle.Repository_error msg) ->
          Printf.printf "repo error: %s\n" msg
      | Error (Lifecycle.Validation_error msg) -> print_endline msg));
  [%expect {|
    Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "open_kb fails when KB not initialised" =
  with_git_root "lc-open-no-init-" (fun root ->
    with_chdir root (fun () ->
      match Lifecycle.open_kb () with
      | Ok _ -> print_endline "unexpected success"
      | Error (Lifecycle.Repository_error msg) ->
          Printf.printf "repo error: %s\n" msg
      | Error (Lifecycle.Validation_error msg) -> print_endline msg));
  [%expect {|
    No knowledge base found. Run 'bs init' first.
  |}]

let%expect_test "open_kb auto-creates db when jsonl exists" =
  with_git_root "lc-open-auto-rebuild-" (fun root ->
    ignore (Lifecycle.init_kb ~directory:(Some root) ~namespace:(Some "kb"));
    let db_file = Filename.concat root ".kbases.db" in
    let jsonl_path = Filename.concat root ".kbases.jsonl" in
    (* Flush an empty JSONL so the file exists, then delete the db *)
    ignore (Jsonl.write ~path:jsonl_path ~namespace:"kb"
      ~todos:[] ~notes:[] ~relations:[]);
    with_root db_file (fun _ -> ());
    Sys.remove db_file;
    Printf.printf "db removed: %b\n" (not (Sys.file_exists db_file));
    Printf.printf "jsonl exists: %b\n"
      (Sys.file_exists (Filename.concat root ".kbases.jsonl"));
    with_chdir root (fun () ->
      match Lifecycle.open_kb () with
      | Error err -> pp_error err
      | Ok (opened, dir) ->
          Printf.printf "opened: true\n";
          Printf.printf "dir matches: %b\n"
            (normalize dir = normalize root);
          Printf.printf "db recreated: %b\n" (Sys.file_exists db_file);
          (match Config.get (Root.config opened) "namespace" with
           | Ok ns -> Printf.printf "namespace: %s\n" ns
           | Error _ -> print_endline "namespace: missing");
          Root.close opened));
  [%expect {|
    db removed: true
    jsonl exists: true
    opened: true
    dir matches: true
    db recreated: true
    namespace: kb
  |}]

let%expect_test "open_kb fails when neither db nor jsonl exist" =
  with_git_root "lc-open-neither-" (fun root ->
    with_chdir root (fun () ->
      match Lifecycle.open_kb () with
      | Ok _ -> print_endline "unexpected success"
      | Error (Lifecycle.Validation_error msg) -> print_endline msg
      | Error (Lifecycle.Repository_error msg) ->
          Printf.printf "repo error: %s\n" msg));
  [%expect {|
    No knowledge base found. Run 'bs init' first.
  |}]
