module E = Kbases.Control.Exception

let%expect_test "invalid_arg1 basic formatting" =
  (try ignore (E.invalid_arg1 "Error: %s" "test") with Invalid_argument msg -> print_endline msg);
  [%expect {| Error: test |}]

let%expect_test "invalid_arg1 with numbers" =
  (try ignore (E.invalid_arg1 "Value %d is invalid" 42) with Invalid_argument msg -> print_endline msg);
  [%expect {| Value 42 is invalid |}]

let%expect_test "invalid_arg1 with single placeholder" =
  (try ignore (E.invalid_arg1 "Value %s is invalid" "test_string") with Invalid_argument msg -> print_endline msg);
  [%expect {| Value test_string is invalid |}]

let%expect_test "invalid_arg2 basic formatting" =
  (try ignore (E.invalid_arg2 "Error: %s %d" "test" 42) with Invalid_argument msg -> print_endline msg);
  [%expect {| Error: test 42 |}]

let%expect_test "invalid_arg2 with string formatting" =
  (try ignore (E.invalid_arg2 "Cannot %s item %s" "find" "missing") with Invalid_argument msg -> print_endline msg);
  [%expect {| Cannot find item missing |}]

let%expect_test "invalid_arg2 with complex formatting" =
  (try ignore (E.invalid_arg2 "Range %d-%d is invalid" 10 5) with Invalid_argument msg -> print_endline msg);
  [%expect {| Range 10-5 is invalid |}]
