module A = Kbases.Control.Assert

let%expect_test "require success case" =
  A.require true;
  print_endline "Success: condition was true";
  [%expect {| Success: condition was true |}]

let%expect_test "require failure with default message" =
  (try ignore (A.require false) with Invalid_argument msg -> print_endline msg);
  [%expect {| Requirement not met |}]

let%expect_test "require failure with custom message" =
  (try ignore (A.require false ~msg:"Custom error message") with Invalid_argument msg -> print_endline msg);
  [%expect {| Custom error message |}]

let%expect_test "requiref success case" =
  A.requiref true "Value %d should be positive" 42;
  print_endline "Success: condition was true";
  [%expect {| Success: condition was true |}]

let%expect_test "requiref failure with int arg" =
  (try ignore (A.requiref false "Value %d is invalid" 42) with Invalid_argument msg -> print_endline msg);
  [%expect {| Value 42 is invalid |}]

let%expect_test "requiref failure with string arg" =
  (try ignore (A.requiref false "Custom validation for %s failed" "test_value") with Invalid_argument msg -> print_endline msg);
  [%expect {| Custom validation for test_value failed |}]

let%expect_test "requiref failure with two args" =
  (try ignore (A.requiref false "Range %d-%d is invalid" 1 10) with Invalid_argument msg -> print_endline msg);
  [%expect {| Range 1-10 is invalid |}]

let%expect_test "requiref failure with two string args" =
  (try ignore (A.requiref false "Range %s-%s is invalid" "start" "end") with Invalid_argument msg -> print_endline msg);
  [%expect {| Range start-end is invalid |}]

let%expect_test "require_string_length success case" =
  A.require_strlen ~name:"field" ~min:2 ~max:4 "abc";
  print_endline "Length within range";
  [%expect {| Length within range |}]

let%expect_test "require_string_length failure includes name and length" =
  (try
     A.require_strlen ~name:"field" ~min:2 ~max:4 "abcde"
   with Invalid_argument msg -> print_endline msg);
  [%expect {| field must be between 2 and 4 characters, got 5 |}]
