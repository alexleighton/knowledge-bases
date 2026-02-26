module Root = Kbases.Repository.Root
module TodoRepo = Kbases.Repository.Todo
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier

let create_git_root = Test_helpers.create_git_root
let with_chdir = Test_helpers.with_chdir
let query_count = Test_helpers.query_count
let query_rows = Test_helpers.query_rows

let pp_error err =
  match err with
  | Service.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | Service.Validation_error msg -> Printf.printf "validation error: %s\n" msg

let expect_ok result f =
  match result with
  | Error err -> pp_error err
  | Ok v -> f v

let with_open_kb f =
  expect_ok (Service.open_kb ()) (fun (root, service) ->
    Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f root service))

let%expect_test "open_kb succeeds and returns functional service" =
  let root = create_git_root "kb-open-happy-" in
  with_chdir root (fun () ->
    expect_ok
      (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb"))
      (fun _ ->
        with_open_kb (fun db_root service ->
          expect_ok
            (Service.add_note service
               ~title:(Title.make "From open_kb")
               ~content:(Content.make "Works"))
            (fun note ->
              Printf.printf "niceid=%s title=%s\n"
                (Identifier.to_string (Note.niceid note))
                (Title.to_string (Note.title note));
              query_count db_root "note";
              query_rows db_root "SELECT niceid, title, status FROM note" [];
              query_rows db_root "SELECT value FROM config WHERE key = 'namespace'" []))));
  [%expect {|
    niceid=kb-0 title=From open_kb
    note=1
    kb-0|From open_kb|active
    kb
  |}]

let unwrap_todo_repo = Test_helpers.unwrap_todo_repo

let with_service f =
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = Service.init root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f root service)

let%expect_test "resolve via Kb_service" =
  with_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix bug") ~content:(Content.make "Details") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    (match Service.resolve service ~identifier:niceid_str with
     | Ok t ->
         Printf.printf "Resolved: %s status=%s\n"
           (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Resolved: kb-0 status=done
    kb-0|done
  |}]
