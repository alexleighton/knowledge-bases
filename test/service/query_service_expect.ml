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

let unwrap_todo_repo = function
  | Ok v -> v
  | Error (TodoRepo.Backend_failure msg) -> failwith ("backend failure: " ^ msg)
  | Error (TodoRepo.Duplicate_niceid niceid) ->
      failwith ("duplicate niceid: " ^ Identifier.to_string niceid)
  | Error (TodoRepo.Not_found _) -> failwith "todo not found"

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
    unwrap_query (QueryService.list service ~entity_type:None ~statuses:[])
    |> print_items);
  [%expect {|
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
