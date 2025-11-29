module A = Kbases.Control.Assert

let%expect_test "require success case" =
  (* Should not raise any exception when condition is true *)
  A.require true;
  print_endline "Success: condition was true";
  [%expect {| Success: condition was true |}]

let%expect_test "require failure with default message" =
  (try ignore (A.require false) with Invalid_argument msg -> print_endline msg);
  [%expect {| Requirement not met |}]

let%expect_test "require failure with custom message" =
  (try ignore (A.require false ~msg:"Custom error message") with Invalid_argument msg -> print_endline msg);
  [%expect {| Custom error message |}]

let%expect_test "require1 success case" =
  (* Should not raise any exception when condition is true *)
  A.require1 true ~msg:"Value %d should be positive" ~arg:42;
  print_endline "Success: condition was true";
  [%expect {| Success: condition was true |}]

let%expect_test "require1 failure with no message provided" =
  (try ignore (A.require1 false) with Invalid_argument msg -> print_endline msg);
  [%expect {| Requirement not met |}]

let%expect_test "require1 failure with message and arg" =
  (try ignore (A.require1 false ~msg:"Value %d is invalid" ~arg:42) with Invalid_argument msg -> print_endline msg);
  [%expect {| Value 42 is invalid |}]

let%expect_test "require1 failure with message and string arg" =
  (try ignore (A.require1 false ~msg:"Custom validation for %s failed" ~arg:"test_value") with Invalid_argument msg -> print_endline msg);
  [%expect {| Custom validation for test_value failed |}]

let%expect_test "require1 failure with only arg (uses default message)" =
  (try ignore (A.require1 false ~arg:"test") with Invalid_argument msg -> print_endline msg);
  [%expect {| Requirement not met |}]

let%expect_test "require2 success case" =
  (* Should not raise any exception when predicate is true *)
  A.require2 true ~msg:"Range %d-%d is invalid" ~arg1:1 ~arg2:10;
  print_endline "Success: predicate was true";
  [%expect {| Success: predicate was true |}]

let%expect_test "require2 failure with no message provided" =
  (try ignore (A.require2 false) with Invalid_argument msg -> print_endline msg);
  [%expect {| Requirement not met |}]

let%expect_test "require2 failure with message and args" =
  (try ignore (A.require2 false ~msg:"Range %d-%d is invalid" ~arg1:1 ~arg2:10) with Invalid_argument msg -> print_endline msg);
  [%expect {| Range 1-10 is invalid |}]

let%expect_test "require2 failure with message and string args" =
  (try ignore (A.require2 false ~msg:"Range %s-%s is invalid" ~arg1:"start" ~arg2:"end") with Invalid_argument msg -> print_endline msg);
  [%expect {| Range start-end is invalid |}]

let%expect_test "require2 failure with only arg1" =
  (try ignore (A.require2 false ~arg1:5) with Invalid_argument msg -> print_endline msg);
  [%expect {| Requirement not met |}]

let%expect_test "require2 failure with only arg2" =
  (try ignore (A.require2 false ~arg2:10) with Invalid_argument msg -> print_endline msg);
  [%expect {| Requirement not met |}]

let%expect_test "require2 failure with only args" =
  (try ignore (A.require2 false ~arg1:"start" ~arg2:"end") with Invalid_argument msg -> print_endline msg);
  [%expect {| Requirement not met |}]

let%expect_test "require_string_length success case" =
  A.require_strlen ~min:2 ~max:4 "abc";
  print_endline "Length within range";
  [%expect {| Length within range |}]

let%expect_test "require_string_length failure with default message" =
  (try
     A.require_strlen ~min:2 ~max:4 "abcde"
   with Invalid_argument msg -> print_endline msg);
  [%expect {| String length must be between 2 and 4, got 5 |}]

let%expect_test "require_string_length failure with custom message" =
  (try
     A.require_strlen ~min:1 ~max:2 ~msg:"value must be 1-2 chars" "toolong"
   with Invalid_argument msg -> print_endline msg);
  [%expect {| value must be 1-2 chars |}]
