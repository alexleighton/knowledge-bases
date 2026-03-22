module Root = Kbases.Repository.Root
module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo
module MutationService = Kbases.Service.Mutation_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier

let unwrap_note_repo = Test_helpers.unwrap_note_repo
let unwrap_todo_repo = Test_helpers.unwrap_todo_repo
let query_rows = Test_helpers.query_rows

let with_mutation_service f =
  Test_helpers.with_service MutationService.init f

let pp_error = Test_helpers.pp_item_error

(* -- Resolve tests -- *)

let%expect_test "resolve open todo sets status to done" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix bug") ~content:(Content.make "Details") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    (match MutationService.resolve service ~identifier:niceid_str with
     | Ok t ->
         Printf.printf "Resolved: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Resolved: kb-0 status=done
    kb-0|done
  |}]

let%expect_test "resolve already-done todo returns nothing to update" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix bug") ~content:(Content.make "Details") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    ignore (MutationService.resolve service ~identifier:niceid_str);
    match MutationService.resolve service ~identifier:niceid_str with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: nothing to update |}]

let%expect_test "resolve a note returns validation error" =
  with_mutation_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Note") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    match MutationService.resolve service ~identifier:niceid_str with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: resolve applies only to todos, but kb-0 is a note
  |}]

let%expect_test "resolve non-existent niceid" =
  with_mutation_service (fun _root service ->
    match MutationService.resolve service ~identifier:"kb-999" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: item not found: kb-999
  |}]

(* -- resolve_many tests -- *)

let%expect_test "resolve_many resolves two todos in input order" =
  with_mutation_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "A") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "B") ()) in
    let id0 = Identifier.to_string (Todo.niceid t0) in
    let id1 = Identifier.to_string (Todo.niceid t1) in
    (match MutationService.resolve_many service ~identifiers:[id0; id1] with
     | Ok todos ->
         List.iter (fun t ->
           Printf.printf "%s status=%s\n"
             (Identifier.to_string (Todo.niceid t))
             (Todo.status_to_string (Todo.status t))) todos
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo ORDER BY niceid" []);
  [%expect {|
    kb-0 status=done
    kb-1 status=done
    kb-0|done
    kb-1|done
  |}]

let%expect_test "resolve_many short-circuits on error" =
  with_mutation_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Good") ~content:(Content.make "A") ()));
    (match MutationService.resolve_many service ~identifiers:["kb-0"; "kb-999"] with
     | Ok _ -> print_endline "unexpected success"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    validation error: item not found: kb-999
    kb-0|done
  |}]

let%expect_test "resolve_many single-element list" =
  with_mutation_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Solo") ~content:(Content.make "A") ()));
    (match MutationService.resolve_many service ~identifiers:["kb-0"] with
     | Ok [t] ->
         Printf.printf "%s status=%s\n"
           (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Ok _ -> print_endline "unexpected list length"
     | Error err -> pp_error err));
  [%expect {|
    kb-0 status=done
  |}]

