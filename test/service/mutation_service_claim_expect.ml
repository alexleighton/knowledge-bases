module Root = Kbases.Repository.Root
module RelationRepo = Kbases.Repository.Relation
module MutationService = Kbases.Service.Mutation_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind

open Test_helpers

let with_mutation_service f =
  with_service MutationService.init f

let pp_error = pp_item_error

let pp_claim_error = function
  | MutationService.Not_a_todo id -> Printf.printf "not a todo: %s\n" id
  | MutationService.Not_open { niceid; status } ->
      Printf.printf "not open: %s (status=%s)\n" niceid status
  | MutationService.Blocked { niceid; blocked_by } ->
      Printf.printf "blocked: %s by [%s]\n" niceid (String.concat "; " blocked_by)
  | MutationService.Nothing_available { stuck_count } ->
      Printf.printf "nothing available: %d stuck\n" stuck_count
  | MutationService.Service_error err -> pp_error err

(* -- Claim tests -- *)

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
    (match MutationService.claim service ~identifier:niceid_str with
     | Ok t ->
         Printf.printf "Claimed: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Error err -> pp_claim_error err);
    query_rows root "SELECT niceid, status FROM todo WHERE niceid = 'kb-0'" []);
  [%expect {|
    Claimed: kb-0 status=in-progress
    kb-0|in-progress
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
     | Error err -> pp_claim_error err);
    query_rows root "SELECT niceid, status FROM todo ORDER BY niceid" []);
  [%expect {|
    Next: kb-1 title=Open task
    kb-0|in-progress
    kb-1|in-progress
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
    (match MutationService.next service with
     | Ok (Some t) ->
         Printf.printf "Next: %s status=%s\n" (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Ok None -> print_endline "none"
     | Error err -> pp_claim_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Next: kb-0 status=in-progress
    kb-0|in-progress
  |}]
