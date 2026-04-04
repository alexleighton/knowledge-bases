module Content = Kbases.Data.Content

let%expect_test "make creates content and to_string returns original text" =
  let c = Content.make "Hello, World!" in
  print_endline (Content.to_string c);
  [%expect {| Hello, World! |}]

let%expect_test "make accepts 1-char and 10000-char content at boundaries" =
  let min_content = Content.make (String.make 1 'x') in
  let max_content = Content.make (String.make 10000 'x') in
  Printf.printf "min=%d max=%d\n"
    (String.length (Content.to_string min_content))
    (String.length (Content.to_string max_content));
  [%expect {| min=1 max=10000 |}]

let%expect_test "make rejects empty string and strings over 10000 characters" =
  let cases = [
    ("", "empty");
    (String.make 10001 'x', "10001 chars");
  ] in
  List.iter (fun (s, label) ->
    try ignore (Content.make s)
    with Invalid_argument msg -> Printf.printf "%s: ERR: %s\n" label msg
  ) cases;
  [%expect {|
    empty: ERR: content must be between 1 and 10000 characters, got 0
    10001 chars: ERR: content must be between 1 and 10000 characters, got 10001
  |}]

let%expect_test "show and pp produce quoted representation" =
  let c = Content.make "My Content" in
  print_endline (Content.show c);
  Format.printf "%a@." Content.pp c;
  [%expect {|
    "My Content"
    "My Content"
  |}]
