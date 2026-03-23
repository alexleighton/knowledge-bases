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
module Timestamp = Kbases.Data.Timestamp

let unwrap_note_repo = Test_helpers.unwrap_note_repo
let unwrap_todo_repo = Test_helpers.unwrap_todo_repo

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

(* -- Sort tests -- *)

let make_clock epoch =
  let r = ref epoch in
  fun () ->
    let t = Timestamp.make !r in
    r := !r + 1;
    t

let%expect_test "list with sort_created default (ascending)" =
  with_query_service (fun root service ->
    let now = make_clock 1000 in
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "Body") ~now ()));
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "Body") ~now ()));
    unwrap_items (QueryService.list service
      { spec with entity_type = Some "todo"; sort = Some Sort_created })
    |> print_items);
  [%expect {|
    kb-0 todo open First
    kb-1 todo open Second
    |}]

let%expect_test "list with sort_created descending" =
  with_query_service (fun root service ->
    let now = make_clock 1000 in
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "Body") ~now ()));
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "Body") ~now ()));
    unwrap_items (QueryService.list service
      { spec with entity_type = Some "todo"; sort = Some Sort_created; ascending = false })
    |> print_items);
  [%expect {|
    kb-1 todo open Second
    kb-0 todo open First
  |}]

(* -- Count tests -- *)

let%expect_test "count_only returns grouped counts" =
  with_query_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "T1") ~content:(Content.make "Body") ()));
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "T2") ~content:(Content.make "Body")
      ~status:Todo.In_Progress ()));
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "N1") ~content:(Content.make "Body") ()));
    match QueryService.list service { spec with count_only = true } with
    | Ok (QueryService.Counts { todos; notes }) ->
        List.iter (fun (s, c) -> Printf.printf "todo %s=%d\n" s c) todos;
        List.iter (fun (s, c) -> Printf.printf "note %s=%d\n" s c) notes
    | Ok (QueryService.Items _) -> print_endline "unexpected items"
    | Error err -> pp_error err);
  [%expect {|
    todo in-progress=1
    todo open=1
    note active=1
  |}]

(* -- Validation tests -- *)

let%expect_test "sort and count cannot both be set" =
  with_query_service (fun _root service ->
    match QueryService.list service
      { spec with sort = Some Sort_created; count_only = true } with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: --sort cannot be combined with --count |}]

let%expect_test "transitive requires exactly one filter" =
  with_query_service (fun _root service ->
    match QueryService.list service { spec with transitive = true } with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: --transitive requires exactly one relation filter |}]

(* -- Relation filter tests -- *)

let%expect_test "relation filter returns related items" =
  with_query_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Source") ~content:(Content.make "Body") ()) in
    let _t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Related") ~content:(Content.make "Body") ()) in
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Unrelated") ~content:(Content.make "Body") ()));
    let rel = Relation.make ~source:(Todo.id t0) ~target:(Todo.id _t1)
      ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true in
    ignore (RelationRepo.create (Root.relation root) rel);
    let filters = [QueryService.{ target = "kb-0"; kind = "depends-on";
                                   direction = Kbases.Service.Graph_service.Outgoing }] in
    unwrap_items (QueryService.list service
      { spec with entity_type = Some "todo"; relation_filters = filters })
    |> print_items);
  [%expect {|
    kb-1 todo open Related
  |}]

let%expect_test "count with type filter returns only that type" =
  with_query_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "T1") ~content:(Content.make "Body") ()));
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "N1") ~content:(Content.make "Body") ()));
    match QueryService.list service
      { spec with entity_type = Some "todo"; count_only = true } with
    | Ok (QueryService.Counts { todos; notes }) ->
        List.iter (fun (s, c) -> Printf.printf "todo %s=%d\n" s c) todos;
        Printf.printf "notes count=%d\n" (List.length notes)
    | Ok (QueryService.Items _) -> print_endline "unexpected items"
    | Error err -> pp_error err);
  [%expect {|
    todo open=1
    notes count=0
  |}]

let%expect_test "count with available returns available count" =
  with_query_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Open") ~content:(Content.make "Body") ()));
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Done") ~content:(Content.make "Body")
      ~status:Todo.Done ()));
    ignore (unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Note") ~content:(Content.make "Body") ()));
    match QueryService.list service
      { spec with available = true; count_only = true } with
    | Ok (QueryService.Counts { todos; notes }) ->
        List.iter (fun (s, c) -> Printf.printf "todo %s=%d\n" s c) todos;
        Printf.printf "notes count=%d\n" (List.length notes)
    | Ok (QueryService.Items _) -> print_endline "unexpected items"
    | Error err -> pp_error err);
  [%expect {|
    todo open=1
    notes count=0
  |}]
