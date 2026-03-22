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

(* -- Archive tests -- *)

let%expect_test "archive active note sets status to archived" =
  with_mutation_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Research") ~content:(Content.make "Findings") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    (match MutationService.archive service ~identifier:niceid_str with
     | Ok n ->
         Printf.printf "Archived: %s status=%s\n" (Identifier.to_string (Note.niceid n))
           (Note.status_to_string (Note.status n))
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM note" []);
  [%expect {|
    Archived: kb-0 status=archived
    kb-0|archived
  |}]

let%expect_test "archive already-archived note returns nothing to update" =
  with_mutation_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Research") ~content:(Content.make "Findings") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    ignore (MutationService.archive service ~identifier:niceid_str);
    match MutationService.archive service ~identifier:niceid_str with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: nothing to update |}]

let%expect_test "archive a todo returns validation error" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Todo") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match MutationService.archive service ~identifier:niceid_str with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: archive applies only to notes, but kb-0 is a todo
  |}]

let%expect_test "archive non-existent niceid" =
  with_mutation_service (fun _root service ->
    match MutationService.archive service ~identifier:"kb-999" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: item not found: kb-999
  |}]

(* -- archive_many tests -- *)

let%expect_test "archive_many archives two notes in input order" =
  with_mutation_service (fun root service ->
    let n0 = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "First") ~content:(Content.make "A") ()) in
    let n1 = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Second") ~content:(Content.make "B") ()) in
    let id0 = Identifier.to_string (Note.niceid n0) in
    let id1 = Identifier.to_string (Note.niceid n1) in
    (match MutationService.archive_many service ~identifiers:[id0; id1] with
     | Ok notes ->
         List.iter (fun n ->
           Printf.printf "%s status=%s\n"
             (Identifier.to_string (Note.niceid n))
             (Note.status_to_string (Note.status n))) notes
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM note ORDER BY niceid" []);
  [%expect {|
    kb-0 status=archived
    kb-1 status=archived
    kb-0|archived
    kb-1|archived
  |}]

let%expect_test "archive_many short-circuits on error" =
  with_mutation_service (fun root service ->
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Good") ~content:(Content.make "A") ()));
    (match MutationService.archive_many service ~identifiers:["kb-0"; "kb-999"] with
     | Ok _ -> print_endline "unexpected success"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM note" []);
  [%expect {|
    validation error: item not found: kb-999
    kb-0|archived
  |}]

let%expect_test "archive_many single-element list" =
  with_mutation_service (fun root service ->
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Solo") ~content:(Content.make "A") ()));
    (match MutationService.archive_many service ~identifiers:["kb-0"] with
     | Ok [n] ->
         Printf.printf "%s status=%s\n"
           (Identifier.to_string (Note.niceid n))
           (Note.status_to_string (Note.status n))
     | Ok _ -> print_endline "unexpected list length"
     | Error err -> pp_error err));
  [%expect {|
    kb-0 status=archived
  |}]
