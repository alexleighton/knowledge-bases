module Note = Kbases.Data.Note
module Id = Kbases.Data.Identifier

let%expect_test "make comprehensive test" =
  let test_cases = [
    (* Success cases *)
    ("test", 1, "Test Title", "Simple note");
    ("abc", 0, "Test Title", "Note with zero ID");
    ("data", 999, "Test Title", "Note with larger ID");
    ("note", 42, "Test Title", "Longer content with special chars: \"quotes\" and | pipes");

    (* Title validation errors *)
    ("test", 1, "", "Some content");  (* empty title *)
    ("test", 1, String.make 101 'x', "Some content");  (* title too long *)

    (* Content validation errors *)
    ("test", 1, "Title", "");  (* empty content *)
    ("test", 1, "Title", String.make 10001 'x');  (* content too long *)
  ] in
  List.iter (fun (ns, id, title, content) ->
    let identifier = Id.make ns id in
    try print_endline (Note.show (Note.make identifier title content))
    with Invalid_argument msg -> Printf.printf "ERR: %s\n" msg
  ) test_cases;
  [%expect {|
    { Note.identifier = test-1; title = "Test Title"; content = "Simple note" }
    { Note.identifier = abc-0; title = "Test Title";
      content = "Note with zero ID" }
    { Note.identifier = data-999; title = "Test Title";
      content = "Note with larger ID" }
    { Note.identifier = note-42; title = "Test Title";
      content = "Longer content with special chars: \"quotes\" and | pipes" }
    ERR: title must be between 1 and 100 characters, got 0
    ERR: title must be between 1 and 100 characters, got 101
    ERR: content must be between 1 and 10000 characters, got 0
    ERR: content must be between 1 and 10000 characters, got 10001
    |}]

let%expect_test "make boundary lengths" =
  let identifier = Id.make "bound" 7 in
  let note_min = Note.make identifier (String.make 1 't') (String.make 1 'c') in
  let note_max = Note.make identifier (String.make 100 't') (String.make 10000 'c') in
  Printf.printf "Boundary lengths: min title=%d content=%d; max title=%d content=%d\n"
    (String.length (Note.title note_min))
    (String.length (Note.content note_min))
    (String.length (Note.title note_max))
    (String.length (Note.content note_max));
  [%expect {| Boundary lengths: min title=1 content=1; max title=100 content=10000 |}]

let%expect_test "accessor functions" =
  let identifier = Id.make "test" 42 in
  let note = Note.make identifier "My Title" "My content" in

  Printf.printf "Identifier: %s\n" (Id.to_string (Note.id note));
  Printf.printf "Title: %S\n" (Note.title note);
  Printf.printf "Content: %S\n" (Note.content note);
  [%expect {|
    Identifier: test-42
    Title: "My Title"
    Content: "My content"
    |}]

let%expect_test "to_string with special characters" =
  let identifier = Id.make "test" 1 in
  let note1 = Note.make identifier "Title with | pipe" "Content with \"quotes\" and \\ backslash" in
  let note2 = Note.make identifier "Normal Title" "Normal content" in

  print_endline (Note.show note1);
  print_endline (Note.show note2);
  [%expect {|
    { Note.identifier = test-1; title = "Title with | pipe";
      content = "Content with \"quotes\" and \\ backslash" }
    { Note.identifier = test-1; title = "Normal Title";
      content = "Normal content" }
    |}]

let%expect_test "pretty printing" =
  let identifier = Id.make "demo" 123 in
  let note = Note.make identifier "Sample Title" "Sample content with \"quotes\"." in

  Format.printf "%a@." Note.pp note;
  [%expect {|
    { Note.identifier = demo-123; title = "Sample Title";
      content = "Sample content with \"quotes\"." }
    |}]
