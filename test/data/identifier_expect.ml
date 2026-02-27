module Id = Kbases.Data.Identifier
module Namespace = Kbases.Data.Namespace

let%expect_test "make comprehensive test" =
  let test_cases = [
    (* Success cases *)
    ("test", 42);
    ("a", 0);
    ("abcde", 1);
    ("ok", 0);
    (* Error cases *)
    ("abcdef", 0);  (* invalid namespace length *)
    ("", 0);        (* empty namespace *)
    ("Te", 0);      (* invalid namespace chars *)
    ("ok", -1);     (* negative raw_id *)
  ] in
  List.iter (fun (namespace, raw_id) ->
    try print_endline (Id.to_string (Id.make namespace raw_id))
    with Invalid_argument msg -> Printf.printf "ERR: %s\n" msg
  ) test_cases;
  [%expect {|
    test-42
    a-0
    abcde-1
    ok-0
    ERR: namespace must be between 1 and 5 characters, got "abcdef"
    ERR: namespace must be between 1 and 5 characters, got ""
    ERR: namespace must match `^[a-z]+$`, got "Te"
    ERR: raw_id must be >= 0, got -1
  |}]

let%expect_test "from_string happy path" =
  (* Test successful parsing *)
  let id = Id.from_string "ok-0" in
  Printf.printf "%s-%d\n" (Namespace.to_string (Id.namespace id)) (Id.raw_id id);
  [%expect {| ok-0 |}]

let%expect_test "from_string invalid format" =
  (try ignore (Id.from_string "oops") with Invalid_argument msg -> print_endline msg);
  [%expect {| Invalid format "oops", expected "namespace-id" |}]

let%expect_test "parse valid input" =
  let result = Id.parse "kb-0" in
  (match result with
   | Ok id ->
       Printf.printf "Ok: namespace=%s raw_id=%d\n"
         (Namespace.to_string (Id.namespace id)) (Id.raw_id id)
   | Error msg -> Printf.printf "Error: %s\n" msg);
  [%expect {| Ok: namespace=kb raw_id=0 |}]

let%expect_test "parse invalid input" =
  let result = Id.parse "oops" in
  (match result with
   | Ok _ -> print_endline "unexpected Ok"
   | Error msg -> Printf.printf "Error: %s\n" msg);
  [%expect {| Error: Invalid format "oops", expected "namespace-id" |}]
