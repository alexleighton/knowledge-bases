module Root = Kbases.Repository.Root
module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo
module QueryService = Kbases.Service.Query_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier

let unwrap_note_repo = Test_helpers.unwrap_note_repo
let unwrap_todo_repo = Test_helpers.unwrap_todo_repo
let query_count = Test_helpers.query_count

let with_query_service f =
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = QueryService.init root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f root service)

let pp_error err =
  match err with
  | QueryService.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | QueryService.Validation_error msg -> Printf.printf "validation error: %s\n" msg

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

let unwrap_query result =
  match result with
  | Ok v -> v
  | Error err -> pp_error err; failwith "unexpected error"

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
    unwrap_query (QueryService.list service ~entity_type:None ~statuses:[])
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
    unwrap_query (QueryService.list service ~entity_type:(Some "todo") ~statuses:["open"])
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
    unwrap_query (QueryService.list service ~entity_type:None ~statuses:["open"; "active"])
    |> print_items);
  [%expect {|
    kb-0 todo open Open todo
    kb-2 note active Active note
  |}]

let%expect_test "list rejects invalid status for entity type" =
  with_query_service (fun _root service ->
    match QueryService.list service ~entity_type:(Some "note") ~statuses:["done"] with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: invalid status "done" for note
  |}]

let%expect_test "list rejects invalid entity type" =
  with_query_service (fun _root service ->
    match QueryService.list service ~entity_type:(Some "banana") ~statuses:[] with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: invalid entity type "banana"
  |}]

module Typeid = Kbases.Data.Uuid.Typeid

let mask_typeid s =
  let underscore_pos = String.index s '_' in
  String.sub s 0 (underscore_pos + 1) ^ "<ID>"

let print_item = function
  | QueryService.Todo_item todo ->
      Printf.printf "todo %s (%s)\nStatus: %s\nTitle:  %s\n\n%s\n"
        (Identifier.to_string (Todo.niceid todo))
        (mask_typeid (Typeid.to_string (Todo.id todo)))
        (Todo.status_to_string (Todo.status todo))
        (Title.to_string (Todo.title todo))
        (Content.to_string (Todo.content todo))
  | QueryService.Note_item note ->
      Printf.printf "note %s (%s)\nStatus: %s\nTitle:  %s\n\n%s\n"
        (Identifier.to_string (Note.niceid note))
        (mask_typeid (Typeid.to_string (Note.id note)))
        (Note.status_to_string (Note.status note))
        (Title.to_string (Note.title note))
        (Content.to_string (Note.content note))

let%expect_test "show todo by niceid" =
  with_query_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix the bug") ~content:(Content.make "Details here") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match QueryService.show service ~identifier:niceid_str with
    | Ok QueryService.{ item; _ } -> print_item item
    | Error err -> pp_error err);
  [%expect {|
    todo kb-0 (todo_<ID>)
    Status: open
    Title:  Fix the bug

    Details here
  |}]

let%expect_test "show note by niceid" =
  with_query_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Research notes") ~content:(Content.make "Findings") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    match QueryService.show service ~identifier:niceid_str with
    | Ok QueryService.{ item; _ } -> print_item item
    | Error err -> pp_error err);
  [%expect {|
    note kb-0 (note_<ID>)
    Status: active
    Title:  Research notes

    Findings
  |}]

let%expect_test "show todo by typeid" =
  with_query_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix the bug") ~content:(Content.make "Details here") ()) in
    let typeid_str = Typeid.to_string (Todo.id todo) in
    match QueryService.show service ~identifier:typeid_str with
    | Ok QueryService.{ item; _ } -> print_item item
    | Error err -> pp_error err);
  [%expect {|
    todo kb-0 (todo_<ID>)
    Status: open
    Title:  Fix the bug

    Details here
  |}]

let%expect_test "show note by typeid" =
  with_query_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Research notes") ~content:(Content.make "Findings") ()) in
    let typeid_str = Typeid.to_string (Note.id note) in
    match QueryService.show service ~identifier:typeid_str with
    | Ok QueryService.{ item; _ } -> print_item item
    | Error err -> pp_error err);
  [%expect {|
    note kb-0 (note_<ID>)
    Status: active
    Title:  Research notes

    Findings
  |}]

let%expect_test "show niceid not found" =
  with_query_service (fun _root service ->
    match QueryService.show service ~identifier:"kb-999" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: item not found: kb-999
  |}]

let%expect_test "show typeid not found" =
  with_query_service (fun _root service ->
    match QueryService.show service ~identifier:"todo_00000000000000000000000000" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: item not found: todo_00000000000000000000000000
  |}]

let%expect_test "show unrecognised input" =
  with_query_service (fun _root service ->
    match QueryService.show service ~identifier:"garbage" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: invalid identifier "garbage" — expected a niceid (e.g. kb-0) or typeid (e.g. todo_01abc...)
  |}]

let%expect_test "show unknown typeid prefix" =
  with_query_service (fun _root service ->
    match QueryService.show service ~identifier:"banana_00000000000000000000000000" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: unknown typeid prefix "banana"
  |}]
