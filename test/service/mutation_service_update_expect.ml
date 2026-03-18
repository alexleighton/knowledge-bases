module Root = Kbases.Repository.Root
module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo
module MutationService = Kbases.Service.Mutation_service
module ItemService = Kbases.Service.Item_service
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

(* -- Update tests -- *)

let%expect_test "update todo status from open to in-progress" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix bug") ~content:(Content.make "Details") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    (match MutationService.update service ~identifier:niceid_str ~status:"in-progress" () with
     | Ok (ItemService.Todo_item t) ->
         Printf.printf "Updated: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Ok (ItemService.Note_item _) -> print_endline "unexpected note"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Updated: kb-0 status=in-progress
    kb-0|in-progress
  |}]

let%expect_test "update note title" =
  with_mutation_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Old title") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    (match MutationService.update service ~identifier:niceid_str
             ~title:(Title.make "New title") () with
     | Ok (ItemService.Note_item n) ->
         Printf.printf "Updated: %s title=%s\n" (Identifier.to_string (Note.niceid n))
           (Title.to_string (Note.title n))
     | Ok (ItemService.Todo_item _) -> print_endline "unexpected todo"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, title FROM note" []);
  [%expect {|
    Updated: kb-0 title=New title
    kb-0|New title
  |}]

let%expect_test "update todo content" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Title") ~content:(Content.make "Old body") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    (match MutationService.update service ~identifier:niceid_str
             ~content:(Content.make "New body") () with
     | Ok (ItemService.Todo_item t) ->
         Printf.printf "Updated: %s content=%s\n" (Identifier.to_string (Todo.niceid t))
           (Content.to_string (Todo.content t))
     | Ok (ItemService.Note_item _) -> print_endline "unexpected note"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, content FROM todo" []);
  [%expect {|
    Updated: kb-0 content=New body
    kb-0|New body
  |}]

let%expect_test "update multiple fields at once" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Old") ~content:(Content.make "Old body") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    (match MutationService.update service ~identifier:niceid_str
             ~status:"done" ~title:(Title.make "New") ~content:(Content.make "New body") () with
     | Ok (ItemService.Todo_item t) ->
         Printf.printf "Updated: %s status=%s title=%s\n"
           (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
           (Title.to_string (Todo.title t))
     | Ok (ItemService.Note_item _) -> print_endline "unexpected note"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, title, content, status FROM todo" []);
  [%expect {|
    Updated: kb-0 status=done title=New
    kb-0|New|New body|done
  |}]

let%expect_test "update with invalid status for entity type" =
  with_mutation_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Note") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    match MutationService.update service ~identifier:niceid_str ~status:"done" () with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: invalid status "done" for note
  |}]

let%expect_test "update with no changes" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Title") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match MutationService.update service ~identifier:niceid_str () with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: nothing to update
  |}]

let%expect_test "update non-existent niceid" =
  with_mutation_service (fun _root service ->
    match MutationService.update service ~identifier:"kb-999" ~status:"done" () with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: item not found: kb-999
  |}]

(* -- Timestamp tests -- *)

let%expect_test "update sets updated_at, preserves created_at" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Title") ~content:(Content.make "Body") ()) in
    let created = Todo.created_at todo in
    let updated_before = Todo.updated_at todo in
    Printf.printf "created=updated initially: %b\n" (created = updated_before);
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match MutationService.update service ~identifier:niceid_str
            ~title:(Title.make "New title") () with
    | Ok (ItemService.Todo_item t) ->
        Printf.printf "created_at preserved: %b\n" (Todo.created_at t = created);
        Printf.printf "updated_at >= created_at: %b\n" (Todo.updated_at t >= created)
    | Ok (ItemService.Note_item _) -> print_endline "unexpected note"
    | Error err -> pp_error err);
  [%expect {|
    created=updated initially: true
    created_at preserved: true
    updated_at >= created_at: true
  |}]

let%expect_test "no-op update does not change updated_at" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Title") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match MutationService.update service ~identifier:niceid_str
            ~title:(Title.make "Title") () with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: nothing to update |}]
