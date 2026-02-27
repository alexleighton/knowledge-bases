module Relation_kind = Kbases.Data.Relation_kind

let try_make s =
  try
    let k = Relation_kind.make s in
    Printf.printf "ok: %s\n" (Relation_kind.to_string k)
  with Invalid_argument msg ->
    Printf.printf "error: %s\n" msg

let%expect_test "valid simple kind" =
  try_make "depends-on";
  [%expect {| ok: depends-on |}]

let%expect_test "valid single char" =
  try_make "x";
  [%expect {| ok: x |}]

let%expect_test "valid alphanumeric with hyphens" =
  try_make "related-to";
  [%expect {| ok: related-to |}]

let%expect_test "valid with digits" =
  try_make "v2-blocks";
  [%expect {| ok: v2-blocks |}]

let%expect_test "reject empty string" =
  try_make "";
  [%expect {| error: relation kind must be between 1 and 50 characters, got 0 |}]

let%expect_test "reject too long" =
  try_make (String.make 51 'a');
  [%expect {| error: relation kind must be between 1 and 50 characters, got 51 |}]

let%expect_test "reject uppercase" =
  try_make "UPPER";
  [%expect {| error: relation kind must match [a-z0-9][a-z0-9-]* and not end with '-' |}]

let%expect_test "reject spaces" =
  try_make "has space";
  [%expect {| error: relation kind must match [a-z0-9][a-z0-9-]* and not end with '-' |}]

let%expect_test "reject leading hyphen" =
  try_make "-leading";
  [%expect {| error: relation kind must match [a-z0-9][a-z0-9-]* and not end with '-' |}]

let%expect_test "reject trailing hyphen" =
  try_make "trailing-";
  [%expect {| error: relation kind must match [a-z0-9][a-z0-9-]* and not end with '-' |}]

let%expect_test "reject underscore" =
  try_make "has_underscore";
  [%expect {| error: relation kind must match [a-z0-9][a-z0-9-]* and not end with '-' |}]

let%expect_test "equal same kinds" =
  let a = Relation_kind.make "depends-on" in
  let b = Relation_kind.make "depends-on" in
  Printf.printf "%b\n" (Relation_kind.equal a b);
  [%expect {| true |}]

let%expect_test "unequal different kinds" =
  let a = Relation_kind.make "depends-on" in
  let b = Relation_kind.make "related-to" in
  Printf.printf "%b\n" (Relation_kind.equal a b);
  [%expect {| false |}]
