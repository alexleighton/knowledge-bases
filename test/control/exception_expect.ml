module E = Kbases.Control.Exception

let run_invalid_arg f =
  try ignore (f ()) with Invalid_argument msg -> print_endline msg

let%expect_test "invalid_arg1 basic formatting" =
  run_invalid_arg (fun () -> E.invalid_arg1 "Error: %s" "test");
  [%expect {| Error: test |}]

let%expect_test "invalid_arg1 with numbers" =
  run_invalid_arg (fun () -> E.invalid_arg1 "Value %d is invalid" 42);
  [%expect {| Value 42 is invalid |}]

let%expect_test "invalid_arg1 with single placeholder" =
  run_invalid_arg (fun () -> E.invalid_arg1 "Value %s is invalid" "test_string");
  [%expect {| Value test_string is invalid |}]

let%expect_test "invalid_arg2 basic formatting" =
  run_invalid_arg (fun () -> E.invalid_arg2 "Error: %s %d" "test" 42);
  [%expect {| Error: test 42 |}]

let%expect_test "invalid_arg2 with string formatting" =
  run_invalid_arg (fun () -> E.invalid_arg2 "Cannot %s item %s" "find" "missing");
  [%expect {| Cannot find item missing |}]

let%expect_test "invalid_arg2 with complex formatting" =
  run_invalid_arg (fun () -> E.invalid_arg2 "Range %d-%d is invalid" 10 5);
  [%expect {| Range 10-5 is invalid |}]

let%expect_test "invalid_arg3 basic formatting" =
  run_invalid_arg (fun () -> E.invalid_arg3 "Error: %s %d %b" "test" 42 true);
  [%expect {| Error: test 42 true |}]

let%expect_test "invalid_arg3 with repeated placeholders" =
  run_invalid_arg (fun () -> E.invalid_arg3 "Coordinates (%d, %d, %d) invalid" 1 2 3);
  [%expect {| Coordinates (1, 2, 3) invalid |}]

let%expect_test "invalid_arg3 with strings" =
  run_invalid_arg (fun () -> E.invalid_arg3 "Cannot %s %s on %s" "find" "entry" "server");
  [%expect {| Cannot find entry on server |}]
