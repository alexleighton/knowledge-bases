module Parse = Kbases.Service.Parse
module Item_service = Kbases.Service.Item_service

let print_error = function
  | Item_service.Validation_error msg -> Printf.printf "Validation_error: %s\n" msg
  | Item_service.Repository_error msg -> Printf.printf "Repository_error: %s\n" msg

let%expect_test "identifier parses niceid" =
  (match Parse.identifier "kb-0" with
   | Ok (Parse.Niceid _) -> print_endline "Ok (Niceid)"
   | Ok (Parse.Typeid _) -> print_endline "Ok (Typeid)"
   | Error err -> print_error err);
  [%expect {| Ok (Niceid) |}]

let%expect_test "identifier parses typeid" =
  (match Parse.identifier "todo_01h455vb4pex5vsknk084sn02q" with
   | Ok (Parse.Niceid _) -> print_endline "Ok (Niceid)"
   | Ok (Parse.Typeid _) -> print_endline "Ok (Typeid)"
   | Error err -> print_error err);
  [%expect {| Ok (Typeid) |}]

let%expect_test "identifier rejects garbage" =
  (match Parse.identifier "garbage" with
   | Ok _ -> print_endline "unexpected Ok"
   | Error err -> print_error err);
  [%expect {| Validation_error: invalid identifier "garbage" — expected a niceid (e.g. kb-0) or typeid (e.g. todo_01abc...) |}]

let%expect_test "todo_status valid" =
  (match Parse.todo_status "open" with
   | Ok _ -> print_endline "Ok"
   | Error err -> print_error err);
  [%expect {| Ok |}]

let%expect_test "todo_status invalid" =
  (match Parse.todo_status "bad" with
   | Ok _ -> print_endline "unexpected Ok"
   | Error err -> print_error err);
  [%expect {| Validation_error: invalid status "bad" for todo |}]

let%expect_test "note_status valid" =
  (match Parse.note_status "active" with
   | Ok _ -> print_endline "Ok"
   | Error err -> print_error err);
  [%expect {| Ok |}]

let%expect_test "note_status invalid" =
  (match Parse.note_status "done" with
   | Ok _ -> print_endline "unexpected Ok"
   | Error err -> print_error err);
  [%expect {| Validation_error: invalid status "done" for note |}]

let%expect_test "relation_kind valid" =
  (match Parse.relation_kind "depends-on" with
   | Ok _ -> print_endline "Ok"
   | Error err -> print_error err);
  [%expect {| Ok |}]

let%expect_test "relation_kind invalid" =
  (match Parse.relation_kind "BAD" with
   | Ok _ -> print_endline "unexpected Ok"
   | Error err -> print_error err);
  [%expect {| Validation_error: relation kind must match [a-z0-9][a-z0-9-]* and not end with '-' |}]

let%expect_test "entity_type valid todo" =
  (match Parse.entity_type "todo" with
   | Ok s -> Printf.printf "Ok: %s\n" s
   | Error err -> print_error err);
  [%expect {| Ok: todo |}]

let%expect_test "entity_type valid note" =
  (match Parse.entity_type "note" with
   | Ok s -> Printf.printf "Ok: %s\n" s
   | Error err -> print_error err);
  [%expect {| Ok: note |}]

let%expect_test "entity_type invalid" =
  (match Parse.entity_type "banana" with
   | Ok _ -> print_endline "unexpected Ok"
   | Error err -> print_error err);
  [%expect {| Validation_error: invalid entity type "banana" |}]
