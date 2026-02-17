module Namespace = Kbases.Data.Namespace

let print_case name =
  Printf.printf "%s -> %s\n" name (Namespace.of_name name)

let%expect_test "namespace acronym samples" =
  List.iter print_case [
    "knowledge-bases";
    "knowledge_bases";
    "My Cool Project";
    "single";
    "a-b-c";
    "CamelCase";
  ];
  [%expect {|
    knowledge-bases -> kb
    knowledge_bases -> kb
    My Cool Project -> mcp
    single -> s
    a-b-c -> abc
    CamelCase -> c
  |}]

let%expect_test "validate namespace constraints" =
  let cases = [ "test"; "a"; "abcde"; ""; "abcdef"; "Te"; "a1" ] in
  List.iter
    (fun ns ->
      match Namespace.validate ns with
      | Ok valid -> Printf.printf "OK: %s\n" (Namespace.to_string valid)
      | Error msg -> Printf.printf "ERR: %s\n" msg)
    cases;
  [%expect {|
    OK: test
    OK: a
    OK: abcde
    ERR: namespace must be between 1 and 5 characters, got ""
    ERR: namespace must be between 1 and 5 characters, got "abcdef"
    ERR: namespace must match `^[a-z]+$`, got "Te"
    ERR: namespace must match `^[a-z]+$`, got "a1"
  |}]
