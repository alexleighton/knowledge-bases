module Note = Kbases.Data.Note
module Id = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid

let%expect_test "make comprehensive test" =
  let test_cases = [
    (* Success cases *)
    ("note_01h455vb4pex5vsknk084sn02q", "test-1", "Test Title", "Simple note");
    ("note_0123456789abcdefghjkmnpqrs", "abc-0", "Test Title", "Note with zero ID");
    ("note_01h455vb4pex5vsknk084sn02r", "data-999", "Test Title", "Note with larger ID");
    ("note_01h455vb4pex5vsknk084sn02s", "note-42", "Test Title",
      "Longer content with special chars: \"quotes\" and | pipes");

    (* Title validation errors *)
    ("note_01h455vb4pex5vsknk084sn02q", "test-1", "", "Some content");  (* empty title *)
    ("note_0123456789abcdefghjkmnpqrs", "test-1", String.make 101 'x', "Some content");  (* title too long *)

    (* Content validation errors *)
    ("note_01h455vb4pex5vsknk084sn02r", "test-1", "Title", "");  (* empty content *)
    ("note_01h455vb4pex5vsknk084sn02s", "test-1", "Title", String.make 10001 'x');  (* content too long *)

    (* TypeId validation errors *)
    ("task_01h455vb4pex5vsknk084sn02t", "test-9", "Title", "Content");  (* wrong prefix *)
  ] in
  List.iter (fun (typeid, niceid, title, content) ->
    let identifier = Id.from_string niceid in
    let tid = Typeid.of_string typeid in
    try print_endline (Note.show (Note.make tid identifier title content))
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
    ERR: title must be between 1 and 100 characters, got 0
    ERR: title must be between 1 and 100 characters, got 101
    ERR: content must be between 1 and 10000 characters, got 0
    ERR: content must be between 1 and 10000 characters, got 10001
    ERR: note TypeId prefix must be "note", got "task"
    |}]

let%expect_test "make boundary lengths" =
  let identifier = Id.from_string "bound-7" in
  let note_min =
    Note.make
      (Typeid.of_string "note_01h455vb4pex5vsknk084sn02q")
      identifier
      (String.make 1 't')
      (String.make 1 'c')
  in
  let note_max =
    Note.make
      (Typeid.of_string "note_0123456789abcdefghjkmnpqrs")
      identifier
      (String.make 100 't')
      (String.make 10000 'c')
  in
  Printf.printf "Boundary lengths: min title=%d content=%d; max title=%d content=%d\n"
    (String.length (Note.title note_min))
    (String.length (Note.content note_min))
    (String.length (Note.title note_max))
    (String.length (Note.content note_max));
  [%expect {| Boundary lengths: min title=1 content=1; max title=100 content=10000 |}]

let%expect_test "accessor functions" =
  let identifier = Id.from_string "test-42" in
  let tid = Typeid.of_string "note_01h455vb4pex5vsknk084sn02r" in
  let note = Note.make tid identifier "My Title" "My content" in
  Printf.printf "TypeId: %s\n" (Typeid.to_string (Note.id note));
  Printf.printf "NiceId: %s\n" (Id.to_string (Note.niceid note));
  Printf.printf "Title: %S\n" (Note.title note);
  Printf.printf "Content: %S\n" (Note.content note);
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
    Note.make tid identifier "Title with | pipe"
    "Content with \"quotes\" and \\ backslash"
  in
  let note2 = Note.make tid identifier "Normal Title" "Normal content" in
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
      "Sample Title"
      "Sample content with \"quotes\"."
  in
  Format.printf "%a@." Note.pp note;
  [%expect {|
    { Note.id = note_01h455vb4pex5vsknk084sn02r; niceid = demo-123;
      title = "Sample Title"; content = "Sample content with \"quotes\"." }
    |}]
