module Root = Kbases.Repository.Root
module Config = Kbases.Repository.Config
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
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

let with_chdir dir f =
  let original = Sys.getcwd () in
  Fun.protect ~finally:(fun () -> Sys.chdir original) (fun () -> Sys.chdir dir; f ())

let expect_ok result f =
  match result with
  | Error err -> pp_error err
  | Ok v -> f v

let with_open_kb f =
  expect_ok (Service.open_kb ()) (fun (root, service) ->
    Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f service))

let with_root db_file f =
  match Root.init ~db_file ~namespace:None with
  | Error (Root.Backend_failure msg) -> Printf.printf "root open failed: %s\n" msg
  | Ok opened ->
      Fun.protect ~finally:(fun () -> Root.close opened) (fun () -> f opened)

let%expect_test "init_kb succeeds with explicit directory and namespace" =
  let root = create_git_root "kb-init-explicit-" in
  expect_ok (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb")) (fun result ->
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
  with_chdir nested (fun () ->
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
  with_chdir dir (fun () ->
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
  with_chdir nested (fun () ->
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

let%expect_test "add_todo returns a todo on success" =
  (match with_service (fun svc ->
     Service.add_todo svc
       ~title:(Title.make "Fix bug")
       ~content:(Content.make "Details")
       ()) with
   | Ok todo ->
       Printf.printf
         "niceid=%s title=%s content=%s status=%s\n"
         (Identifier.to_string (Todo.niceid todo))
         (Title.to_string (Todo.title todo))
         (Content.to_string (Todo.content todo))
         (Todo.status_to_string (Todo.status todo))
   | Error err -> pp_error err);
  [%expect {| niceid=kb-0 title=Fix bug content=Details status=open |}]

let%expect_test "add_todo accepts explicit status" =
  (match with_service (fun svc ->
     Service.add_todo svc
       ~title:(Title.make "Ship")
       ~content:(Content.make "Soon")
       ~status:Todo.In_Progress
       ()) with
   | Ok todo ->
       Printf.printf "status=%s\n" (Todo.status_to_string (Todo.status todo))
   | Error err -> pp_error err);
  [%expect {| status=in-progress |}]

let%expect_test "open_kb succeeds and returns functional service" =
  let root = create_git_root "kb-open-happy-" in
  with_chdir root (fun () ->
    expect_ok
      (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb"))
      (fun _ ->
        with_open_kb (fun service ->
          expect_ok
            (Service.add_note service
               ~title:(Title.make "From open_kb")
               ~content:(Content.make "Works"))
            (fun note ->
              Printf.printf "niceid=%s title=%s\n"
                (Identifier.to_string (Note.niceid note))
                (Title.to_string (Note.title note))))));
  [%expect {| niceid=kb-0 title=From open_kb |}]

let%expect_test "open_kb fails when not in a git repo" =
  let dir = Filename.temp_dir "kb-open-no-git-" "" in
  with_chdir dir (fun () ->
    match Service.open_kb () with
    | Ok _ -> print_endline "unexpected success"
    | Error (Service.Repository_error msg) ->
        Printf.printf "repo error: %s\n" msg
    | Error (Service.Validation_error msg) -> print_endline msg);
  [%expect {|
    Not inside a git repository. Run 'bs add' from within a git repository.
  |}]

let%expect_test "open_kb fails when KB not initialised" =
  let root = create_git_root "kb-open-no-init-" in
  with_chdir root (fun () ->
    match Service.open_kb () with
    | Ok _ -> print_endline "unexpected success"
    | Error (Service.Repository_error msg) ->
        Printf.printf "repo error: %s\n" msg
    | Error (Service.Validation_error msg) -> print_endline msg);
  [%expect {|
    No knowledge base found. Run 'bs init' first.
  |}]
