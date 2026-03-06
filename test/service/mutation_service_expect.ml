module Root = Kbases.Repository.Root
module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo
module RelationRepo = Kbases.Repository.Relation
module MutationService = Kbases.Service.Mutation_service
module ItemService = Kbases.Service.Item_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind

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

(* -- Claim tests -- *)

let pp_claim_error = function
  | MutationService.Not_a_todo id -> Printf.printf "not a todo: %s\n" id
  | MutationService.Not_open { niceid; status } ->
      Printf.printf "not open: %s (status=%s)\n" niceid status
  | MutationService.Blocked { niceid; blocked_by } ->
      Printf.printf "blocked: %s by [%s]\n" niceid (String.concat "; " blocked_by)
  | MutationService.Nothing_available { stuck_count } ->
      Printf.printf "nothing available: %d stuck\n" stuck_count
  | MutationService.Service_error err -> pp_error err

let make_blocking_rel ~source ~target =
  Relation.make ~source:(Todo.id source) ~target:(Todo.id target)
    ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true

let%expect_test "claim open unblocked todo succeeds" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    (match MutationService.claim service ~identifier:niceid_str with
     | Ok t ->
         Printf.printf "Claimed: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Error err -> pp_claim_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Claimed: kb-0 status=in-progress
    kb-0|in-progress
  |}]

let%expect_test "claim a note returns Not_a_todo" =
  with_mutation_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Note") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    match MutationService.claim service ~identifier:niceid_str with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_claim_error err);
  [%expect {|
    not a todo: kb-0
  |}]

let%expect_test "claim non-open todo returns Not_open" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body")
      ~status:Todo.In_Progress ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match MutationService.claim service ~identifier:niceid_str with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_claim_error err);
  [%expect {|
    not open: kb-0 (status=in-progress)
  |}]

let%expect_test "claim blocked todo returns Blocked" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Blocked") ~content:(Content.make "Body") ()) in
    let dep = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Dependency") ~content:(Content.make "Body") ()) in
    let rel = make_blocking_rel ~source:todo ~target:dep in
    ignore (RelationRepo.create (Root.relation root) rel);
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match MutationService.claim service ~identifier:niceid_str with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_claim_error err);
  [%expect {|
    blocked: kb-0 by [kb-1]
  |}]

let%expect_test "claim todo with depends-on note succeeds" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()) in
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Design") ~content:(Content.make "Body") ()) in
    let rel = Relation.make ~source:(Todo.id todo) ~target:(Note.id note)
      ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true in
    ignore (RelationRepo.create (Root.relation root) rel);
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match MutationService.claim service ~identifier:niceid_str with
    | Ok t ->
        Printf.printf "Claimed: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
          (Todo.status_to_string (Todo.status t))
    | Error err -> pp_claim_error err);
  [%expect {|
    Claimed: kb-0 status=in-progress
  |}]

let%expect_test "claim todo with done dependency succeeds" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()) in
    let dep = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Done dep") ~content:(Content.make "Body")
      ~status:Todo.Done ()) in
    let rel = make_blocking_rel ~source:todo ~target:dep in
    ignore (RelationRepo.create (Root.relation root) rel);
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match MutationService.claim service ~identifier:niceid_str with
    | Ok t ->
        Printf.printf "Claimed: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
          (Todo.status_to_string (Todo.status t))
    | Error err -> pp_claim_error err);
  [%expect {|
    Claimed: kb-0 status=in-progress
  |}]

(* -- Next tests -- *)

let%expect_test "next selects single open unblocked todo" =
  with_mutation_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()));
    (match MutationService.next service with
     | Ok (Some t) ->
         Printf.printf "Next: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Ok None -> print_endline "none available"
     | Error err -> pp_claim_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Next: kb-0 status=in-progress
    kb-0|in-progress
  |}]

let%expect_test "next skips blocked todo and selects next unblocked" =
  with_mutation_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Blocked") ~content:(Content.make "Body") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Dependency") ~content:(Content.make "Body") ()) in
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Unblocked") ~content:(Content.make "Body") ()));
    let rel = make_blocking_rel ~source:t0 ~target:t1 in
    ignore (RelationRepo.create (Root.relation root) rel);
    (match MutationService.next service with
     | Ok (Some t) ->
         Printf.printf "Next: %s title=%s\n" (Identifier.to_string (Todo.niceid t))
           (Title.to_string (Todo.title t))
     | Ok None -> print_endline "none available"
     | Error err -> pp_claim_error err);
    query_rows root "SELECT niceid, status FROM todo ORDER BY niceid" []);
  [%expect {|
    Next: kb-1 title=Dependency
    kb-0|open
    kb-1|in-progress
    kb-2|open
  |}]

let%expect_test "next returns None when no open todos" =
  with_mutation_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Done") ~content:(Content.make "Body")
      ~status:Todo.Done ()));
    match MutationService.next service with
    | Ok None -> print_endline "none"
    | Ok (Some _) -> print_endline "unexpected some"
    | Error err -> pp_claim_error err);
  [%expect {|
    none
  |}]

let%expect_test "next returns Nothing_available when all open are blocked" =
  with_mutation_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Blocked A") ~content:(Content.make "Body") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Blocked B") ~content:(Content.make "Body") ()) in
    let dep = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Dep") ~content:(Content.make "Body")
      ~status:Todo.In_Progress ()) in
    ignore (RelationRepo.create (Root.relation root) (make_blocking_rel ~source:t0 ~target:dep));
    ignore (RelationRepo.create (Root.relation root) (make_blocking_rel ~source:t1 ~target:dep));
    match MutationService.next service with
    | Ok _ -> print_endline "unexpected ok"
    | Error err -> pp_claim_error err);
  [%expect {|
    nothing available: 2 stuck
  |}]

let%expect_test "next ignores in-progress todos" =
  with_mutation_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "In progress") ~content:(Content.make "Body")
      ~status:Todo.In_Progress ()));
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Open task") ~content:(Content.make "Body") ()));
    (match MutationService.next service with
     | Ok (Some t) ->
         Printf.printf "Next: %s title=%s\n" (Identifier.to_string (Todo.niceid t))
           (Title.to_string (Todo.title t))
     | Ok None -> print_endline "none"
     | Error err -> pp_claim_error err));
  [%expect {|
    Next: kb-1 title=Open task
  |}]

let%expect_test "next with depends-on note does not block" =
  with_mutation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()) in
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Design") ~content:(Content.make "Body") ()) in
    let rel = Relation.make ~source:(Todo.id todo) ~target:(Note.id note)
      ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true in
    ignore (RelationRepo.create (Root.relation root) rel);
    match MutationService.next service with
    | Ok (Some t) ->
        Printf.printf "Next: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
          (Todo.status_to_string (Todo.status t))
    | Ok None -> print_endline "none"
    | Error err -> pp_claim_error err);
  [%expect {|
    Next: kb-0 status=in-progress
  |}]
