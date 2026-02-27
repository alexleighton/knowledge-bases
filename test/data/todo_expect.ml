module Todo = Kbases.Data.Todo
module Id = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content

let sample_todo_id = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs"

let statuses = [Todo.Open; Todo.In_Progress; Todo.Done]

let%expect_test "make comprehensive test" =
  let test_cases = [
    (* Success cases *)
    ("todo_01h455vb4pex5vsknk084sn02q", "task-1", "Todo Title", "Simple content", Todo.Open);
    ("todo_0123456789abcdefghjkmnpqrs", "abc-0",  "Todo Title", "Content with zero ID", Todo.In_Progress);

    (* TypeId validation error *)
    ("note_01h455vb4pex5vsknk084sn02q", "task-9", "Title", "Content", Todo.Open);
  ] in
  List.iter (fun (typeid, niceid, title, content, status) ->
    let identifier = Id.from_string niceid in
    let tid = Typeid.of_string typeid in
    try
      print_endline (Todo.show
        (Todo.make tid identifier (Title.make title) (Content.make content) status))
    with Invalid_argument msg -> Printf.printf "ERR: %s\n" msg
  ) test_cases;
  [%expect {|
    { Todo.id = todo_01h455vb4pex5vsknk084sn02q; niceid = task-1;
      title = "Todo Title"; content = "Simple content"; status = Todo.Open }
    { Todo.id = todo_0123456789abcdefghjkmnpqrs; niceid = abc-0;
      title = "Todo Title"; content = "Content with zero ID";
      status = Todo.In_Progress }
    ERR: todo TypeId prefix must be "todo", got "note"
  |}]

let%expect_test "make_id generation" =
  let id = Todo.make_id () in
  Printf.printf "Prefix: %s\n" (Typeid.get_prefix id);
  [%expect {| Prefix: todo |}]

let%expect_test "accessor functions" =
  let identifier = Id.from_string "task-42" in
  let tid = Typeid.of_string "todo_01h455vb4pex5vsknk084sn02r" in
  let todo = Todo.make tid identifier (Title.make "My Title") (Content.make "My content") Todo.Done in
  Printf.printf "TypeId: %s\n" (Typeid.to_string (Todo.id todo));
  Printf.printf "NiceId: %s\n" (Id.to_string (Todo.niceid todo));
  Printf.printf "Title: %S\n" (Title.to_string (Todo.title todo));
  Printf.printf "Content: %S\n" (Content.to_string (Todo.content todo));
  Printf.printf "Status: %s\n" (Todo.status_to_string (Todo.status todo));
  [%expect {|
    TypeId: todo_01h455vb4pex5vsknk084sn02r
    NiceId: task-42
    Title: "My Title"
    Content: "My content"
    Status: done
  |}]

let%expect_test "make boundary lengths" =
  let identifier = Id.from_string "bound-7" in
  let todo_min =
    Todo.make
      (Typeid.of_string "todo_01h455vb4pex5vsknk084sn02q")
      identifier
      (Title.make (String.make 1 't'))
      (Content.make (String.make 1 'c'))
      Todo.Open
  in
  let todo_max =
    Todo.make
      (Typeid.of_string "todo_0123456789abcdefghjkmnpqrs")
      identifier
      (Title.make (String.make 100 't'))
      (Content.make (String.make 10000 'c'))
      Todo.Open
  in
  Printf.printf "Boundary lengths: min title=%d content=%d; max title=%d content=%d\n"
    (String.length (Title.to_string (Todo.title todo_min)))
    (String.length (Content.to_string (Todo.content todo_min)))
    (String.length (Title.to_string (Todo.title todo_max)))
    (String.length (Content.to_string (Todo.content todo_max)));
  [%expect {| Boundary lengths: min title=1 content=1; max title=100 content=10000 |}]

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
  let todo = Todo.make sample_todo_id identifier
    (Title.make "Task") (Content.make "Review") Todo.In_Progress in
  Format.printf "%a@." Todo.pp todo;
  [%expect {|
    { Todo.id = todo_0123456789abcdefghjkmnpqrs; niceid = todo-5; title = "Task";
      content = "Review"; status = Todo.In_Progress }
    |}]

let%expect_test "with_status changes status, preserves other fields" =
  let identifier = Id.from_string "task-1" in
  let tid = Typeid.of_string "todo_01h455vb4pex5vsknk084sn02q" in
  let todo = Todo.make tid identifier (Title.make "Fix bug") (Content.make "Details") Todo.Open in
  let updated = Todo.with_status todo Todo.Done in
  Printf.printf "Status: %s\n" (Todo.status_to_string (Todo.status updated));
  Printf.printf "Title: %s\n" (Title.to_string (Todo.title updated));
  Printf.printf "Content: %s\n" (Content.to_string (Todo.content updated));
  Printf.printf "NiceId: %s\n" (Id.to_string (Todo.niceid updated));
  Printf.printf "Id: %s\n" (Typeid.to_string (Todo.id updated));
  [%expect {|
    Status: done
    Title: Fix bug
    Content: Details
    NiceId: task-1
    Id: todo_01h455vb4pex5vsknk084sn02q
  |}]

let%expect_test "with_title changes title, preserves other fields" =
  let identifier = Id.from_string "task-2" in
  let tid = Typeid.of_string "todo_01h455vb4pex5vsknk084sn02r" in
  let todo = Todo.make tid identifier (Title.make "Old title") (Content.make "Body") Todo.In_Progress in
  let updated = Todo.with_title todo (Title.make "New title") in
  Printf.printf "Title: %s\n" (Title.to_string (Todo.title updated));
  Printf.printf "Status: %s\n" (Todo.status_to_string (Todo.status updated));
  Printf.printf "Content: %s\n" (Content.to_string (Todo.content updated));
  [%expect {|
    Title: New title
    Status: in-progress
    Content: Body
  |}]

let%expect_test "status_of_string valid round-trip" =
  List.iter (fun status ->
    let s = Todo.status_to_string status in
    Printf.printf "%s -> %s\n" s
      (match Todo.status_of_string s with
       | Ok v -> Todo.status_to_string v
       | Error msg -> "Error: " ^ msg)
  ) statuses;
  [%expect {|
    open -> open
    in-progress -> in-progress
    done -> done
  |}]

let%expect_test "status_of_string invalid input" =
  Printf.printf "%s\n"
    (match Todo.status_of_string "pending" with
     | Ok _ -> "unexpected Ok"
     | Error msg -> "Error: " ^ msg);
  [%expect {| Error: Invalid status "pending" |}]

let%expect_test "with_content changes content, preserves other fields" =
  let identifier = Id.from_string "task-3" in
  let tid = Typeid.of_string "todo_01h455vb4pex5vsknk084sn02s" in
  let todo = Todo.make tid identifier (Title.make "Title") (Content.make "Old body") Todo.Open in
  let updated = Todo.with_content todo (Content.make "New body") in
  Printf.printf "Content: %s\n" (Content.to_string (Todo.content updated));
  Printf.printf "Title: %s\n" (Title.to_string (Todo.title updated));
  Printf.printf "Status: %s\n" (Todo.status_to_string (Todo.status updated));
  [%expect {|
    Content: New body
    Title: Title
    Status: open
  |}]
