module Root = Kbases.Repository.Root
module Config = Kbases.Repository.Config
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier

let create_git_root prefix =
  let root = Filename.temp_dir prefix "" in
  Unix.mkdir (Filename.concat root ".git") 0o755;
  root

let starts_with s prefix =
  let s_len = String.length s in
  let p_len = String.length prefix in
  s_len >= p_len && String.sub s 0 p_len = prefix

let normalize path =
  try Unix.realpath path with
  | Unix.Unix_error _ -> path

let with_service f =
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = Service.init root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f service)

let pp_error err =
  match err with
  | Service.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | Service.Validation_error msg -> Printf.printf "validation error: %s\n" msg

let%expect_test "init_kb succeeds with explicit directory and namespace" =
  let root = create_git_root "kb-init-explicit-" in
  match Service.init_kb ~directory:(Some root) ~namespace:(Some "kb") with
  | Error err -> pp_error err
  | Ok result ->
      Printf.printf "db exists: %b\n" (Sys.file_exists result.db_file);
      (match Root.init ~db_file:result.db_file ~namespace:None with
       | Error (Root.Backend_failure msg) ->
           Printf.printf "root open failed: %s\n" msg
       | Ok opened ->
           (match Config.get (Root.config opened) "namespace" with
            | Ok ns -> Printf.printf "namespace persisted: %b\n" (ns = "kb")
            | Error _ -> print_endline "namespace persisted: false");
           Root.close opened);
  [%expect {|
    db exists: true
    namespace persisted: true
  |}]

let%expect_test "init_kb rejects non-git root directory" =
  let dir = Filename.temp_dir "kb-init-not-git-" "" in
  match Service.init_kb ~directory:(Some dir) ~namespace:(Some "kb") with
  | Ok _ -> print_endline "unexpected success"
  | Error (Service.Repository_error msg) ->
      Printf.printf "repo error: %s\n" msg
  | Error (Service.Validation_error msg) ->
      Printf.printf "is-dir-error: %b\n"
        (starts_with msg "Directory is not a git repository root: ");
  [%expect {|
    is-dir-error: true
  |}]

let%expect_test "init_kb rejects invalid explicit namespace" =
  let root = create_git_root "kb-init-invalid-ns-" in
  match Service.init_kb ~directory:(Some root) ~namespace:(Some "TooLong") with
  | Ok _ -> print_endline "unexpected success"
  | Error (Service.Repository_error msg) ->
      Printf.printf "repo error: %s\n" msg
  | Error (Service.Validation_error msg) ->
      Printf.printf "%s\n" msg;
  [%expect {|
    namespace must be between 1 and 5 characters, got "TooLong"
  |}]

let%expect_test "init_kb guards against re-initialization" =
  let root = create_git_root "kb-init-reinit-" in
  ignore (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb"));
  match Service.init_kb ~directory:(Some root) ~namespace:(Some "kb") with
  | Ok _ -> print_endline "unexpected success"
  | Error (Service.Repository_error msg) ->
      Printf.printf "repo error: %s\n" msg
  | Error (Service.Validation_error msg) ->
      Printf.printf "already-init-error: %b\n"
        (starts_with msg "Knowledge base already initialised at ");
  [%expect {|
    already-init-error: true
  |}]

let%expect_test "init_kb resolves repo root from cwd when directory is None" =
  let root = create_git_root "kb-init-no-args-" in
  let nested = Filename.concat root "nested" in
  Unix.mkdir nested 0o755;
  let original = Sys.getcwd () in
  Fun.protect
    ~finally:(fun () -> Sys.chdir original)
    (fun () ->
      Sys.chdir nested;
      match Service.init_kb ~directory:None ~namespace:(Some "kb") with
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
  let dir = Filename.temp_dir "kb-init-outside-" "" in
  let original = Sys.getcwd () in
  Fun.protect
    ~finally:(fun () -> Sys.chdir original)
    (fun () ->
      Sys.chdir dir;
      match Service.init_kb ~directory:None ~namespace:(Some "kb") with
      | Ok _ -> print_endline "unexpected success"
      | Error (Service.Repository_error msg) -> Printf.printf "repo error: %s\n" msg
      | Error (Service.Validation_error msg) -> print_endline msg);
  [%expect {|
    Not inside a git repository. Use -d to specify a directory.
  |}]

let%expect_test "init_kb reports invalid derived namespace" =
  let parent = Filename.temp_dir "kb-init-parent-" "" in
  let root = Filename.concat parent "kb-2bad" in
  Unix.mkdir root 0o755;
  Unix.mkdir (Filename.concat root ".git") 0o755;
  let nested = Filename.concat root "nested" in
  Unix.mkdir nested 0o755;
  let original = Sys.getcwd () in
  Fun.protect
    ~finally:(fun () -> Sys.chdir original)
    (fun () ->
      Sys.chdir nested;
      match Service.init_kb ~directory:None ~namespace:None with
      | Ok _ -> print_endline "unexpected success"
      | Error (Service.Repository_error msg) -> Printf.printf "repo error: %s\n" msg
      | Error (Service.Validation_error msg) ->
          Printf.printf "derived-error: %b\n" (starts_with msg "Derived namespace"));
  [%expect {|
    derived-error: true
  |}]

let%expect_test "add_note returns a note on success" =
  (match with_service (fun svc ->
     Service.add_note svc
       ~title:(Title.make "Reminder")
       ~content:(Content.make "Pay bills")) with
   | Ok note ->
       Printf.printf
         "niceid=%s title=%s content=%s\n"
         (Identifier.to_string (Note.niceid note))
         (Title.to_string (Note.title note))
         (Content.to_string (Note.content note))
   | Error err -> pp_error err);
  [%expect {| niceid=kb-0 title=Reminder content=Pay bills |}]
