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
