module Todo = Kbases.Data.Todo
module Id = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Timestamp = Kbases.Data.Timestamp

let sample_todo_id = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs"

let statuses = [Todo.Open; Todo.In_Progress; Todo.Done]

let make_todo ?(status = Todo.Open) ?(created_at = 0) ?(updated_at = 0)
    tid niceid title content =
  Todo.make (Typeid.of_string tid) (Id.from_string niceid)
    (Title.make title) (Content.make content) status
    ~created_at:(Timestamp.make created_at) ~updated_at:(Timestamp.make updated_at)

let%expect_test "make succeeds with valid inputs and rejects wrong TypeId prefix" =
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
        (Todo.make tid identifier (Title.make title) (Content.make content) status ~created_at:(Timestamp.make 0) ~updated_at:(Timestamp.make 0)))
    with Invalid_argument msg -> Printf.printf "ERR: %s\n" msg
  ) test_cases;
  [%expect {|
    { Todo.id = todo_01h455vb4pex5vsknk084sn02q; niceid = task-1;
      title = "Todo Title"; content = "Simple content"; status = Todo.Open;
      created_at = 0; updated_at = 0 }
    { Todo.id = todo_0123456789abcdefghjkmnpqrs; niceid = abc-0;
      title = "Todo Title"; content = "Content with zero ID";
      status = Todo.In_Progress; created_at = 0; updated_at = 0 }
    ERR: todo TypeId prefix must be "todo", got "note"
    |}]

let%expect_test "make_id returns a typeid with todo prefix" =
  let id = Todo.make_id () in
  Printf.printf "Prefix: %s\n" (Typeid.get_prefix id);
  [%expect {| Prefix: todo |}]

let%expect_test "accessors return title, content, status, and niceid from constructed todo" =
  let todo = make_todo ~status:Todo.Done
    "todo_01h455vb4pex5vsknk084sn02r" "task-42" "My Title" "My content" in
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

let%expect_test "make accepts boundary title and content lengths" =
  let identifier = Id.from_string "bound-7" in
  let todo_min =
    Todo.make
      (Typeid.of_string "todo_01h455vb4pex5vsknk084sn02q")
      identifier
      (Title.make (String.make 1 't'))
      (Content.make (String.make 1 'c'))
      Todo.Open ~created_at:(Timestamp.make 0) ~updated_at:(Timestamp.make 0)
  in
  let todo_max =
    Todo.make
      (Typeid.of_string "todo_0123456789abcdefghjkmnpqrs")
      identifier
      (Title.make (String.make 100 't'))
      (Content.make (String.make 10000 'c'))
      Todo.Open ~created_at:(Timestamp.make 0) ~updated_at:(Timestamp.make 0)
  in
  Printf.printf "Boundary lengths: min title=%d content=%d; max title=%d content=%d\n"
    (String.length (Title.to_string (Todo.title todo_min)))
    (String.length (Content.to_string (Todo.content todo_min)))
    (String.length (Title.to_string (Todo.title todo_max)))
    (String.length (Content.to_string (Todo.content todo_max)));
  [%expect {| Boundary lengths: min title=1 content=1; max title=100 content=10000 |}]

let%expect_test "status_to_string and status_from_string round-trip all statuses" =
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

let%expect_test "show and pp produce formatted todo representation" =
  let todo = make_todo ~status:Todo.In_Progress
    "todo_0123456789abcdefghjkmnpqrs" "todo-5" "Task" "Review" in
  Format.printf "%a@." Todo.pp todo;
  [%expect {|
    { Todo.id = todo_0123456789abcdefghjkmnpqrs; niceid = todo-5; title = "Task";
      content = "Review"; status = Todo.In_Progress; created_at = 0;
      updated_at = 0 }
    |}]

let%expect_test "with_status changes status, preserves other fields" =
  let todo = make_todo "todo_01h455vb4pex5vsknk084sn02q" "task-1" "Fix bug" "Details" in
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
  let todo = make_todo ~status:Todo.In_Progress
    "todo_01h455vb4pex5vsknk084sn02r" "task-2" "Old title" "Body" in
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
  let todo = make_todo "todo_01h455vb4pex5vsknk084sn02s" "task-3" "Title" "Old body" in
  let updated = Todo.with_content todo (Content.make "New body") in
  Printf.printf "Content: %s\n" (Content.to_string (Todo.content updated));
  Printf.printf "Title: %s\n" (Title.to_string (Todo.title updated));
  Printf.printf "Status: %s\n" (Todo.status_to_string (Todo.status updated));
  [%expect {|
    Content: New body
    Title: Title
    Status: open
  |}]

let%expect_test "timestamp accessors return expected values" =
  let todo = make_todo ~created_at:1710000000 ~updated_at:1710003600
    "todo_01h455vb4pex5vsknk084sn02q" "task-10" "Timed" "Body" in
  Printf.printf "created_at: %d\n" (Timestamp.to_epoch (Todo.created_at todo));
  Printf.printf "updated_at: %d\n" (Timestamp.to_epoch (Todo.updated_at todo));
  [%expect {|
    created_at: 1710000000
    updated_at: 1710003600
  |}]

let%expect_test "satisfies Entity.S module type" =
  let _check : (module Kbases.Data.Entity.S) = (module Todo) in
  print_endline "ok";
  [%expect {| ok |}]

let%expect_test "entity_name is todo" =
  Printf.printf "%s\n" Todo.entity_name;
  [%expect {| todo |}]

let%expect_test "default_excluded_status is Done" =
  Printf.printf "%s\n" (Todo.status_to_string Todo.default_excluded_status);
  [%expect {| done |}]

let%expect_test "with_updated_at returns copy with new value" =
  let todo = make_todo ~created_at:1710000000 ~updated_at:1710000000
    "todo_01h455vb4pex5vsknk084sn02r" "task-11" "Original" "Body" in
  let updated = Todo.with_updated_at todo (Timestamp.make 1710099999) in
  Printf.printf "created_at: %d\n" (Timestamp.to_epoch (Todo.created_at updated));
  Printf.printf "updated_at: %d\n" (Timestamp.to_epoch (Todo.updated_at updated));
  Printf.printf "title: %s\n" (Title.to_string (Todo.title updated));
  [%expect {|
    created_at: 1710000000
    updated_at: 1710099999
    title: Original
  |}]
