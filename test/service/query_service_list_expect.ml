module Root = Kbases.Repository.Root
module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo
module RelationRepo = Kbases.Repository.Relation
module QueryService = Kbases.Service.Query_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind

let unwrap_note_repo = Test_helpers.unwrap_note_repo
let unwrap_todo_repo = Test_helpers.unwrap_todo_repo
let query_count = Test_helpers.query_count

let with_query_service f =
  Test_helpers.with_service QueryService.init f

let pp_error = Test_helpers.pp_item_error

let print_items items =
  List.iter (function
    | QueryService.Todo_item todo ->
        Printf.printf "%s todo %s %s\n"
          (Identifier.to_string (Todo.niceid todo))
          (Todo.status_to_string (Todo.status todo))
          (Title.to_string (Todo.title todo))
    | QueryService.Note_item note ->
        Printf.printf "%s note %s %s\n"
          (Identifier.to_string (Note.niceid note))
          (Note.status_to_string (Note.status note))
          (Title.to_string (Note.title note)))
    items

let unwrap_items result =
  match result with
  | Ok (QueryService.Items v) -> v
  | Ok (QueryService.Counts _) -> failwith "unexpected counts"
  | Error err -> pp_error err; failwith "unexpected error"

let spec = QueryService.default_list_spec

let make_blocking_rel = Test_helpers.make_blocking_rel

let%expect_test "list defaults exclude done and archived" =
  with_query_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Open todo") ~content:(Content.make "Body") ()));
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Active note") ~content:(Content.make "Body") ()));
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Done todo") ~content:(Content.make "Body")
      ~status:Todo.Done ()));
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Archived note") ~content:(Content.make "Body")
      ~status:Note.Archived ()));
    (* Verify all four rows exist in the DB *)
    query_count root "todo";
    query_count root "note";
    (* Service filtering returns only open/active items *)
    unwrap_items (QueryService.list service spec)
    |> print_items);
  [%expect {|
    todo=2
    note=2
    kb-0 todo open Open todo
    kb-1 note active Active note
  |}]

let%expect_test "list filters by type and status" =
  with_query_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Open todo") ~content:(Content.make "Body") ()));
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Done todo") ~content:(Content.make "Body")
      ~status:Todo.Done ()));
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Active note") ~content:(Content.make "Body") ()));
    unwrap_items (QueryService.list service { spec with entity_type = Some "todo"; statuses = ["open"] })
    |> print_items);
  [%expect {|
    kb-0 todo open Open todo
  |}]

let%expect_test "list combines statuses across types" =
  with_query_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Open todo") ~content:(Content.make "Body") ()));
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "In progress") ~content:(Content.make "Body")
      ~status:Todo.In_Progress ()));
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Active note") ~content:(Content.make "Body") ()));
    unwrap_items (QueryService.list service { spec with statuses = ["open"; "active"] })
    |> print_items);
  [%expect {|
    kb-0 todo open Open todo
    kb-2 note active Active note
  |}]

let%expect_test "list rejects invalid status for entity type" =
  with_query_service (fun _root service ->
    match QueryService.list service { spec with entity_type = Some "note"; statuses = ["done"] } with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: invalid status "done" for note
  |}]

let%expect_test "list rejects invalid entity type" =
  with_query_service (fun _root service ->
    match QueryService.list service { spec with entity_type = Some "banana" } with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: invalid entity type "banana"
  |}]

let%expect_test "list available returns only open unblocked todos" =
  with_query_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Unblocked") ~content:(Content.make "Body") ()));
    let todo_b = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Blocked") ~content:(Content.make "Body") ()) in
    let _todo_c = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Dependency") ~content:(Content.make "Body") ()) in
    let rel = make_blocking_rel ~source:todo_b ~target:_todo_c in
    ignore (RelationRepo.create (Root.relation root) rel);
    unwrap_items (QueryService.list service { spec with available = true })
    |> print_items);
  [%expect {|
    kb-0 todo open Unblocked
    kb-2 todo open Dependency
  |}]

let%expect_test "list available excludes blocked even with done blocker resolved" =
  with_query_service (fun root service ->
    let todo_a = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Blocked") ~content:(Content.make "Body") ()) in
    let dep = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Dep done") ~content:(Content.make "Body")
      ~status:Todo.Done ()) in
    let rel = make_blocking_rel ~source:todo_a ~target:dep in
    ignore (RelationRepo.create (Root.relation root) rel);
    (* todo_a depends on dep which is done, so todo_a is unblocked *)
    unwrap_items (QueryService.list service { spec with available = true })
    |> print_items);
  [%expect {|
    kb-0 todo open Blocked
  |}]

let%expect_test "list available returns empty when no open todos" =
  with_query_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Done") ~content:(Content.make "Body")
      ~status:Todo.Done ()));
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "A note") ~content:(Content.make "Body") ()));
    unwrap_items (QueryService.list service { spec with available = true })
    |> print_items);
  [%expect {| |}]

let%expect_test "list available ignores notes" =
  with_query_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Open todo") ~content:(Content.make "Body") ()));
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Active note") ~content:(Content.make "Body") ()));
    unwrap_items (QueryService.list service { spec with available = true })
    |> print_items);
  [%expect {|
    kb-0 todo open Open todo
  |}]
