module E = Kbases.Control.Exception

let run_invalid_arg f =
  try ignore (f ()) with Invalid_argument msg -> print_endline msg

let%expect_test "invalid_argf with string" =
  run_invalid_arg (fun () -> E.invalid_argf "Error: %s" "test");
  [%expect {| Error: test |}]

let%expect_test "invalid_argf with number" =
  run_invalid_arg (fun () -> E.invalid_argf "Value %d is invalid" 42);
  [%expect {| Value 42 is invalid |}]

let%expect_test "invalid_argf with two args" =
  run_invalid_arg (fun () -> E.invalid_argf "Error: %s %d" "test" 42);
  [%expect {| Error: test 42 |}]

let%expect_test "invalid_argf with two strings" =
  run_invalid_arg (fun () -> E.invalid_argf "Cannot %s item %s" "find" "missing");
  [%expect {| Cannot find item missing |}]

let%expect_test "invalid_argf with three args" =
  run_invalid_arg (fun () -> E.invalid_argf "Error: %s %d %b" "test" 42 true);
  [%expect {| Error: test 42 true |}]

let%expect_test "invalid_argf with three ints" =
  run_invalid_arg (fun () -> E.invalid_argf "Coordinates (%d, %d, %d) invalid" 1 2 3);
  [%expect {| Coordinates (1, 2, 3) invalid |}]
