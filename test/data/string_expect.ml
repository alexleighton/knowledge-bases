module String = Kbases.Data.String
module C = Kbases.Data.Char

let%expect_test "for_all predicate coverage" =
  let cases = [
    ("all lowercase", C.is_lowercase, "abcxyz");
    ("mixed case fails lowercase", C.is_lowercase, "abC");
    ("digits succeed", C.is_digit, "0123456789");
    ("digits reject letter", C.is_digit, "42a");
    ("empty string always true", C.is_uppercase, "");
    ("hex digits accept hex letters", C.is_hex_digit, "af09");
    ("hex digits reject g", C.is_hex_digit, "g0");
  ] in
  List.iter (fun (label, pred, s) ->
    Printf.printf "%s %S -> %b\n" label s (String.for_all pred s)
  ) cases;
  [%expect {|
    all lowercase "abcxyz" -> true
    mixed case fails lowercase "abC" -> false
    digits succeed "0123456789" -> true
    digits reject letter "42a" -> false
    empty string always true "" -> true
    hex digits accept hex letters "af09" -> true
    hex digits reject g "g0" -> false
  |}]

let print_rsplit sep s =
  Printf.printf "rsplit '%c' %S -> " sep s;
  match String.rsplit ~sep s with
  | None -> print_endline "None"
  | Some (left, right) -> Printf.printf "Some (%S, %S)\n" left right

let%expect_test "rsplit edge cases" =
  List.iter (fun (sep, s) -> print_rsplit sep s)
    [ ('-', "abc-def-ghi");
      (':', "no-colon");
      ('/', "/leading");
      ('.', "trailing.");
      ('=', "one=two=three");
    ];
  [%expect {|
    rsplit '-' "abc-def-ghi" -> Some ("abc-def", "ghi")
    rsplit ':' "no-colon" -> None
    rsplit '/' "/leading" -> Some ("", "leading")
    rsplit '.' "trailing." -> Some ("trailing", "")
    rsplit '=' "one=two=three" -> Some ("one=two", "three")
    |}]

