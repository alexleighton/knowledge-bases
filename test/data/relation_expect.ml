module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module Typeid = Kbases.Data.Uuid.Typeid

let src = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs"
let tgt = Typeid.of_string "note_0123456789abcdefghjkmnpqrs"

let%expect_test "is_blocking true when blocking:true" =
  let rel = Relation.make ~source:src ~target:tgt
    ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true in
  Printf.printf "is_blocking=%b\n" (Relation.is_blocking rel);
  [%expect {| is_blocking=true |}]

let%expect_test "is_blocking false when blocking:false" =
  let rel = Relation.make ~source:src ~target:tgt
    ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:false in
  Printf.printf "is_blocking=%b\n" (Relation.is_blocking rel);
  [%expect {| is_blocking=false |}]

let%expect_test "blocking is independent of relation kind" =
  let rel_related = Relation.make ~source:src ~target:tgt
    ~kind:(Relation_kind.make "related-to") ~bidirectional:true ~blocking:true in
  let rel_custom = Relation.make ~source:src ~target:tgt
    ~kind:(Relation_kind.make "custom-kind") ~bidirectional:false ~blocking:true in
  Printf.printf "related-to blocking=%b\n" (Relation.is_blocking rel_related);
  Printf.printf "custom-kind blocking=%b\n" (Relation.is_blocking rel_custom);
  [%expect {|
    related-to blocking=true
    custom-kind blocking=true
  |}]

let%expect_test "pp includes blocking indicator" =
  let blocking = Relation.make ~source:src ~target:tgt
    ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true in
  let not_blocking = Relation.make ~source:src ~target:tgt
    ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:false in
  Printf.printf "blocking: %s\n" (Relation.show blocking);
  Printf.printf "not blocking: %s\n" (Relation.show not_blocking);
  [%expect {|
    blocking: (todo_0123456789abcdefghjkmnpqrs) -[depends-on B]-> (note_0123456789abcdefghjkmnpqrs)
    not blocking: (todo_0123456789abcdefghjkmnpqrs) -[depends-on]-> (note_0123456789abcdefghjkmnpqrs)
  |}]
