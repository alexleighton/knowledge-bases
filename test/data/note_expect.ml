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
        (Note.make tid identifier (Title.make title) (Content.make content)))
    with Invalid_argument msg -> Printf.printf "ERR: %s\n" msg
  ) test_cases;
  [%expect {|
    { Note.id = note_01h455vb4pex5vsknk084sn02q; niceid = test-1;
      title = "Test Title"; content = "Simple note" }
    { Note.id = note_0123456789abcdefghjkmnpqrs; niceid = abc-0;
      title = "Test Title"; content = "Note with zero ID" }
    { Note.id = note_01h455vb4pex5vsknk084sn02r; niceid = data-999;
      title = "Test Title"; content = "Note with larger ID" }
    { Note.id = note_01h455vb4pex5vsknk084sn02s; niceid = note-42;
      title = "Test Title";
      content = "Longer content with special chars: \"quotes\" and | pipes" }
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
  in
  let note_max =
    Note.make
      (Typeid.of_string "note_0123456789abcdefghjkmnpqrs")
      identifier
      (Title.make (String.make 100 't'))
      (Content.make (String.make 10000 'c'))
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
  let note = Note.make tid identifier (Title.make "My Title") (Content.make "My content") in
  Printf.printf "TypeId: %s\n" (Typeid.to_string (Note.id note));
  Printf.printf "NiceId: %s\n" (Id.to_string (Note.niceid note));
  Printf.printf "Title: %S\n" (Title.to_string (Note.title note));
  Printf.printf "Content: %S\n" (Content.to_string (Note.content note));
  [%expect {|
    TypeId: note_01h455vb4pex5vsknk084sn02r
    NiceId: test-42
    Title: "My Title"
    Content: "My content"
    |}]

let%expect_test "to_string with special characters" =
  let identifier = Id.from_string "test-1" in
  let tid = Typeid.of_string "note_01h455vb4pex5vsknk084sn02q" in
  let note1 =
    Note.make tid identifier
      (Title.make "Title with | pipe")
      (Content.make "Content with \"quotes\" and \\ backslash")
  in
  let note2 =
    Note.make tid identifier
      (Title.make "Normal Title")
      (Content.make "Normal content")
  in
  print_endline (Note.show note1);
  print_endline (Note.show note2);
  [%expect {|
    { Note.id = note_01h455vb4pex5vsknk084sn02q; niceid = test-1;
      title = "Title with | pipe";
      content = "Content with \"quotes\" and \\ backslash" }
    { Note.id = note_01h455vb4pex5vsknk084sn02q; niceid = test-1;
      title = "Normal Title"; content = "Normal content" }
    |}]

let%expect_test "pretty printing" =
  let identifier = Id.from_string "demo-123" in
  let note =
    Note.make
      (Typeid.of_string "note_01h455vb4pex5vsknk084sn02r")
      identifier
      (Title.make "Sample Title")
      (Content.make "Sample content with \"quotes\".")
  in
  Format.printf "%a@." Note.pp note;
  [%expect {|
    { Note.id = note_01h455vb4pex5vsknk084sn02r; niceid = demo-123;
      title = "Sample Title"; content = "Sample content with \"quotes\"." }
    |}]
