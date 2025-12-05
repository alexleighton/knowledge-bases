module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Id = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid

let sample_note_id = Typeid.of_string "note_0123456789abcdefghjkmnpqrs"

let statuses = [Todo.Open; Todo.In_Progress; Todo.Done]

let%expect_test "make and accessors" =
  let identifier = Id.from_string "todo-1" in
  let note = Note.make sample_note_id identifier "Todo Title" "Todo content" in
  List.iter (fun status ->
    let todo = Todo.make note status in
    Printf.printf "%s -> id=%s status=%s\n"
      (Note.title (Todo.note todo))
      (Id.to_string (Todo.id todo))
      (Todo.status_to_string (Todo.status todo))
  ) statuses;
  [%expect {|
    Todo Title -> id=todo-1 status=open
    Todo Title -> id=todo-1 status=in-progress
    Todo Title -> id=todo-1 status=done
  |}]

let%expect_test "status conversions" =
  List.iter (fun status ->
    let as_string = Todo.status_to_string status in
    let round_tripped = Todo.status_from_string as_string in
    Printf.printf "%s -> %b\n" as_string (status = round_tripped)
  ) statuses;
  [%expect {|
    open -> true
    in-progress -> true
    done -> true
  |}]

let%expect_test "status_from_string invalid input" =
  (try ignore (Todo.status_from_string "pending")
   with Invalid_argument msg -> print_endline msg);
  [%expect {| Invalid status "pending" |}]

let%expect_test "pretty printing" =
  let identifier = Id.from_string "todo-5" in
  let note = Note.make sample_note_id identifier "Task" "Review" in
  let todo = Todo.make note Todo.In_Progress in
  Format.printf "%a@." Todo.pp todo;
  [%expect {|
    { Todo.note =
      { Note.id = note_0123456789abcdefghjkmnpqrs; niceid = todo-5;
        title = "Task"; content = "Review" };
      status = Todo.In_Progress }
  |}]

