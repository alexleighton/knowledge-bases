module Root = Kbases.Repository.Root
module MutationService = Kbases.Service.Mutation_service
module ItemService = Kbases.Service.Item_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier

open Test_helpers

let with_mutation_service f =
  with_service MutationService.init f

let pp_error = pp_item_error

(* -- Reopen tests -- *)

let%expect_test "reopen resolved todo sets status to open" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix bug") ~content:(Content.make "Details") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    ignore (MutationService.resolve service ~identifier:niceid_str);
    (match MutationService.reopen service ~identifier:niceid_str with
     | Ok (ItemService.Todo_item t) ->
         Printf.printf "Reopened: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Ok (ItemService.Note_item _) -> print_endline "unexpected note"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Reopened: kb-0 status=open
    kb-0|open
  |}]

let%expect_test "reopen archived note sets status to active" =
  with_mutation_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Research") ~content:(Content.make "Findings") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    ignore (MutationService.archive service ~identifier:niceid_str);
    (match MutationService.reopen service ~identifier:niceid_str with
     | Ok (ItemService.Note_item n) ->
         Printf.printf "Reactivated: %s status=%s\n" (Identifier.to_string (Note.niceid n))
           (Note.status_to_string (Note.status n))
     | Ok (ItemService.Todo_item _) -> print_endline "unexpected todo"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM note" []);
  [%expect {|
    Reactivated: kb-0 status=active
    kb-0|active
  |}]

let%expect_test "reopen open todo returns validation error" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match MutationService.reopen service ~identifier:niceid_str with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: kb-0 is not in a terminal state (status: open)
  |}]

let%expect_test "reopen non-existent item returns error" =
  with_mutation_service (fun _root service ->
    match MutationService.reopen service ~identifier:"kb-999" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: item not found: kb-999
  |}]

(* -- reopen_many tests -- *)

let pp_item = function
  | ItemService.Todo_item t ->
      Printf.printf "%s type=todo status=%s\n"
        (Identifier.to_string (Todo.niceid t))
        (Todo.status_to_string (Todo.status t))
  | ItemService.Note_item n ->
      Printf.printf "%s type=note status=%s\n"
        (Identifier.to_string (Note.niceid n))
        (Note.status_to_string (Note.status n))

let%expect_test "reopen_many reopens todo and note in input order" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "A") ()) in
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Note") ~content:(Content.make "B") ()) in
    let tid = Identifier.to_string (Todo.niceid todo) in
    let nid = Identifier.to_string (Note.niceid note) in
    ignore (MutationService.resolve service ~identifier:tid);
    ignore (MutationService.archive service ~identifier:nid);
    (match MutationService.reopen_many service ~identifiers:[tid; nid] with
     | Ok items -> List.iter pp_item items
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo" [];
    query_rows root "SELECT niceid, status FROM note" []);
  [%expect {|
    kb-0 type=todo status=open
    kb-1 type=note status=active
    kb-0|open
    kb-1|active
  |}]

let%expect_test "reopen_many short-circuits on non-terminal item" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Done") ~content:(Content.make "A") ()) in
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Open") ~content:(Content.make "B") ()));
    let tid = Identifier.to_string (Todo.niceid todo) in
    ignore (MutationService.resolve service ~identifier:tid);
    (match MutationService.reopen_many service ~identifiers:[tid; "kb-1"] with
     | Ok _ -> print_endline "unexpected success"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo ORDER BY niceid" []);
  [%expect {|
    validation error: kb-1 is not in a terminal state (status: open)
    kb-0|open
    kb-1|open
  |}]

let%expect_test "reopen_many single-element list" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Solo") ~content:(Content.make "A") ()) in
    let tid = Identifier.to_string (Todo.niceid todo) in
    ignore (MutationService.resolve service ~identifier:tid);
    (match MutationService.reopen_many service ~identifiers:[tid] with
     | Ok [item] -> pp_item item
     | Ok _ -> print_endline "unexpected list length"
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    kb-0 type=todo status=open
    kb-0|open
  |}]
