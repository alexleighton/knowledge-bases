module Title = Kbases.Data.Title

let%expect_test "make and to_string" =
  let t = Title.make "Hello, World!" in
  print_endline (Title.to_string t);
  [%expect {| Hello, World! |}]

let%expect_test "boundary lengths" =
  let min_title = Title.make (String.make 1 'x') in
  let max_title = Title.make (String.make 100 'x') in
  Printf.printf "min=%d max=%d\n"
    (String.length (Title.to_string min_title))
    (String.length (Title.to_string max_title));
  [%expect {| min=1 max=100 |}]

let%expect_test "validation errors" =
  let cases = [
    ("", "empty");
    (String.make 101 'x', "101 chars");
  ] in
  List.iter (fun (s, label) ->
    try ignore (Title.make s)
    with Invalid_argument msg -> Printf.printf "%s: ERR: %s\n" label msg
  ) cases;
  [%expect {|
    empty: ERR: title must be between 1 and 100 characters, got 0
    101 chars: ERR: title must be between 1 and 100 characters, got 101
  |}]

let%expect_test "show and pp" =
  let t = Title.make "My Title" in
  print_endline (Title.show t);
  Format.printf "%a@." Title.pp t;
  [%expect {|
    "My Title"
    "My Title"
  |}]
