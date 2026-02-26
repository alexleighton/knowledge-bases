module Note = Kbases.Data.Note
module Id = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content

let%expect_test "make comprehensive test" =
  let test_cases = [
    (* Success cases *)
    ("note_01h455vb4pex5vsknk084sn02q", "test-1", "Test Title", "Simple note");
    ("note_0123456789abcdefghjkmnpqrs", "abc-0", "Test Title", "Note with zero ID");
    ("note_01h455vb4pex5vsknk084sn02r", "data-999", "Test Title", "Note with larger ID");
    ("note_01h455vb4pex5vsknk084sn02s", "note-42", "Test Title",
      "Longer content with special chars: \"quotes\" and | pipes");

    (* TypeId validation error *)
    ("task_01h455vb4pex5vsknk084sn02t", "test-9", "Title", "Content");
  ] in
  List.iter (fun (typeid, niceid, title, content) ->
    let identifier = Id.from_string niceid in
    let tid = Typeid.of_string typeid in
    try
      print_endline (Note.show
        (Note.make tid identifier (Title.make title) (Content.make content) Note.Active))
    with Invalid_argument msg -> Printf.printf "ERR: %s\n" msg
  ) test_cases;
  [%expect {|
    { Note.id = note_01h455vb4pex5vsknk084sn02q; niceid = test-1;
      title = "Test Title"; content = "Simple note"; status = Note.Active }
    { Note.id = note_0123456789abcdefghjkmnpqrs; niceid = abc-0;
      title = "Test Title"; content = "Note with zero ID"; status = Note.Active }
    { Note.id = note_01h455vb4pex5vsknk084sn02r; niceid = data-999;
      title = "Test Title"; content = "Note with larger ID"; status = Note.Active
      }
    { Note.id = note_01h455vb4pex5vsknk084sn02s; niceid = note-42;
      title = "Test Title";
      content = "Longer content with special chars: \"quotes\" and | pipes";
      status = Note.Active }
    ERR: note TypeId prefix must be "note", got "task"
    |}]

let%expect_test "make boundary lengths" =
  let identifier = Id.from_string "bound-7" in
  let note_min =
    Note.make
      (Typeid.of_string "note_01h455vb4pex5vsknk084sn02q")
      identifier
      (Title.make (String.make 1 't'))
      (Content.make (String.make 1 'c'))
      Note.Active
  in
  let note_max =
    Note.make
      (Typeid.of_string "note_0123456789abcdefghjkmnpqrs")
      identifier
      (Title.make (String.make 100 't'))
      (Content.make (String.make 10000 'c'))
      Note.Archived
  in
  Printf.printf "Boundary lengths: min title=%d content=%d; max title=%d content=%d\n"
    (String.length (Title.to_string (Note.title note_min)))
    (String.length (Content.to_string (Note.content note_min)))
    (String.length (Title.to_string (Note.title note_max)))
    (String.length (Content.to_string (Note.content note_max)));
  [%expect {| Boundary lengths: min title=1 content=1; max title=100 content=10000 |}]

let%expect_test "accessor functions" =
  let identifier = Id.from_string "test-42" in
  let tid = Typeid.of_string "note_01h455vb4pex5vsknk084sn02r" in
  let note = Note.make tid identifier (Title.make "My Title") (Content.make "My content") Note.Archived in
  Printf.printf "TypeId: %s\n" (Typeid.to_string (Note.id note));
  Printf.printf "NiceId: %s\n" (Id.to_string (Note.niceid note));
  Printf.printf "Title: %S\n" (Title.to_string (Note.title note));
  Printf.printf "Content: %S\n" (Content.to_string (Note.content note));
  Printf.printf "Status: %s\n" (Note.status_to_string (Note.status note));
  [%expect {|
    TypeId: note_01h455vb4pex5vsknk084sn02r
    NiceId: test-42
    Title: "My Title"
    Content: "My content"
    Status: archived
    |}]

let%expect_test "to_string with special characters" =
  let identifier = Id.from_string "test-1" in
  let tid = Typeid.of_string "note_01h455vb4pex5vsknk084sn02q" in
  let note1 =
    Note.make tid identifier
      (Title.make "Title with | pipe")
      (Content.make "Content with \"quotes\" and \\ backslash")
      Note.Active
  in
  let note2 =
    Note.make tid identifier
      (Title.make "Normal Title")
      (Content.make "Normal content")
      Note.Active
  in
  print_endline (Note.show note1);
  print_endline (Note.show note2);
  [%expect {|
    { Note.id = note_01h455vb4pex5vsknk084sn02q; niceid = test-1;
      title = "Title with | pipe";
      content = "Content with \"quotes\" and \\ backslash"; status = Note.Active
      }
    { Note.id = note_01h455vb4pex5vsknk084sn02q; niceid = test-1;
      title = "Normal Title"; content = "Normal content"; status = Note.Active }
    |}]

let%expect_test "pretty printing" =
  let identifier = Id.from_string "demo-123" in
  let note =
    Note.make
      (Typeid.of_string "note_01h455vb4pex5vsknk084sn02r")
      identifier
      (Title.make "Sample Title")
      (Content.make "Sample content with \"quotes\".")
      Note.Active
  in
  Format.printf "%a@." Note.pp note;
  [%expect {|
    { Note.id = note_01h455vb4pex5vsknk084sn02r; niceid = demo-123;
      title = "Sample Title"; content = "Sample content with \"quotes\".";
      status = Note.Active }
    |}]

let%expect_test "status conversion helpers" =
  let open Note in
  let statuses = [Active; Archived] in
  List.iter (fun s ->
    let as_string = status_to_string s in
    let round_trip = status_from_string as_string in
    Printf.printf "%s -> %s\n" as_string (status_to_string round_trip)
  ) statuses;
  [%expect {|
    active -> active
    archived -> archived
  |}]

let%expect_test "status_from_string rejects invalid input" =
  (try
     ignore (Note.status_from_string "bad-status")
   with Invalid_argument msg -> Printf.printf "ERR: %s\n" msg);
  [%expect {|
    ERR: Invalid status "bad-status"
    |}]

let%expect_test "with_status changes status, preserves other fields" =
  let identifier = Id.from_string "test-1" in
  let tid = Typeid.of_string "note_01h455vb4pex5vsknk084sn02q" in
  let note = Note.make tid identifier (Title.make "My note") (Content.make "Body") Note.Active in
  let updated = Note.with_status note Note.Archived in
  Printf.printf "Status: %s\n" (Note.status_to_string (Note.status updated));
  Printf.printf "Title: %s\n" (Title.to_string (Note.title updated));
  Printf.printf "Content: %s\n" (Content.to_string (Note.content updated));
  Printf.printf "NiceId: %s\n" (Id.to_string (Note.niceid updated));
  Printf.printf "Id: %s\n" (Typeid.to_string (Note.id updated));
  [%expect {|
    Status: archived
    Title: My note
    Content: Body
    NiceId: test-1
    Id: note_01h455vb4pex5vsknk084sn02q
  |}]

let%expect_test "with_title changes title, preserves other fields" =
  let identifier = Id.from_string "test-2" in
  let tid = Typeid.of_string "note_01h455vb4pex5vsknk084sn02r" in
  let note = Note.make tid identifier (Title.make "Old title") (Content.make "Body") Note.Archived in
  let updated = Note.with_title note (Title.make "New title") in
  Printf.printf "Title: %s\n" (Title.to_string (Note.title updated));
  Printf.printf "Status: %s\n" (Note.status_to_string (Note.status updated));
  Printf.printf "Content: %s\n" (Content.to_string (Note.content updated));
  [%expect {|
    Title: New title
    Status: archived
    Content: Body
  |}]

let%expect_test "with_content changes content, preserves other fields" =
  let identifier = Id.from_string "test-3" in
  let tid = Typeid.of_string "note_01h455vb4pex5vsknk084sn02s" in
  let note = Note.make tid identifier (Title.make "Title") (Content.make "Old body") Note.Active in
  let updated = Note.with_content note (Content.make "New body") in
  Printf.printf "Content: %s\n" (Content.to_string (Note.content updated));
  Printf.printf "Title: %s\n" (Title.to_string (Note.title updated));
  Printf.printf "Status: %s\n" (Note.status_to_string (Note.status updated));
  [%expect {|
    Content: New body
    Title: Title
    Status: active
  |}]
