module Root = Kbases.Repository.Root
module ShowService = Kbases.Service.Show_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid

open Test_helpers

let with_show_service f =
  with_service ShowService.init f

let pp_error = pp_item_error

let mask_typeid s =
  let underscore_pos = String.index s '_' in
  String.sub s 0 (underscore_pos + 1) ^ "<ID>"

let print_item = function
  | ShowService.Todo_item todo ->
      Printf.printf "todo %s (%s)\nStatus: %s\nTitle:  %s\n\n%s\n"
        (Identifier.to_string (Todo.niceid todo))
        (mask_typeid (Typeid.to_string (Todo.id todo)))
        (Todo.status_to_string (Todo.status todo))
        (Title.to_string (Todo.title todo))
        (Content.to_string (Todo.content todo))
  | ShowService.Note_item note ->
      Printf.printf "note %s (%s)\nStatus: %s\nTitle:  %s\n\n%s\n"
        (Identifier.to_string (Note.niceid note))
        (mask_typeid (Typeid.to_string (Note.id note)))
        (Note.status_to_string (Note.status note))
        (Title.to_string (Note.title note))
        (Content.to_string (Note.content note))

let%expect_test "show todo by niceid" =
  with_show_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix the bug") ~content:(Content.make "Details here") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    match ShowService.show service ~identifier:niceid_str with
    | Ok ShowService.{ item; _ } -> print_item item
    | Error err -> pp_error err);
  [%expect {|
    todo kb-0 (todo_<ID>)
    Status: open
    Title:  Fix the bug

    Details here
  |}]

let%expect_test "show note by niceid" =
  with_show_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Research notes") ~content:(Content.make "Findings") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    match ShowService.show service ~identifier:niceid_str with
    | Ok ShowService.{ item; _ } -> print_item item
    | Error err -> pp_error err);
  [%expect {|
    note kb-0 (note_<ID>)
    Status: active
    Title:  Research notes

    Findings
  |}]

let%expect_test "show todo by typeid" =
  with_show_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix the bug") ~content:(Content.make "Details here") ()) in
    let typeid_str = Typeid.to_string (Todo.id todo) in
    match ShowService.show service ~identifier:typeid_str with
    | Ok ShowService.{ item; _ } -> print_item item
    | Error err -> pp_error err);
  [%expect {|
    todo kb-0 (todo_<ID>)
    Status: open
    Title:  Fix the bug

    Details here
  |}]

let%expect_test "show note by typeid" =
  with_show_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Research notes") ~content:(Content.make "Findings") ()) in
    let typeid_str = Typeid.to_string (Note.id note) in
    match ShowService.show service ~identifier:typeid_str with
    | Ok ShowService.{ item; _ } -> print_item item
    | Error err -> pp_error err);
  [%expect {|
    note kb-0 (note_<ID>)
    Status: active
    Title:  Research notes

    Findings
  |}]

let%expect_test "show niceid not found" =
  with_show_service (fun _root service ->
    match ShowService.show service ~identifier:"kb-999" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: item not found: kb-999
  |}]

let%expect_test "show typeid not found" =
  with_show_service (fun _root service ->
    match ShowService.show service ~identifier:"todo_00000000000000000000000000" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: item not found: todo_00000000000000000000000000
  |}]

let%expect_test "show unrecognised input" =
  with_show_service (fun _root service ->
    match ShowService.show service ~identifier:"garbage" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: invalid identifier "garbage" — expected a niceid (e.g. kb-0) or typeid (e.g. todo_01abc...)
  |}]

let%expect_test "show unknown typeid prefix" =
  with_show_service (fun _root service ->
    match ShowService.show service ~identifier:"banana_00000000000000000000000000" with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: unknown typeid prefix "banana"
  |}]
