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
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = MutationService.init root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f root service)

let pp_error = function
  | ItemService.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | ItemService.Validation_error msg -> Printf.printf "validation error: %s\n" msg

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
