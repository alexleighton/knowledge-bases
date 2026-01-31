module Niceid = Kbases.Repository.Niceid
module Typeid = Kbases.Data.Uuid.Typeid
module Identifier = Kbases.Data.Identifier

let%expect_test "allocate increments from zero" =
  let db = Sqlite3.db_open ":memory:" in
  match Niceid.init ~db ~namespace:"nt" with
  | Error (Niceid.Backend_failure msg) ->
      Printf.printf "init error: %s\n" msg
  | Ok repo ->
      let tid1 = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
      let tid2 = Typeid.of_string "note_0123456789abcdefghjkmnpqrt" in
      let print_result tid =
        match Niceid.allocate repo tid with
        | Ok ident -> Printf.printf "%s -> %d\n" (Typeid.to_string tid) (Identifier.raw_id ident)
        | Error (Niceid.Backend_failure msg) -> Printf.printf "alloc error: %s\n" msg
      in
      print_result tid1;
      print_result tid2;
      ignore (Sqlite3.db_close db);
  [%expect {|
    note_0123456789abcdefghjkmnpqrs -> 0
    note_0123456789abcdefghjkmnpqrt -> 1
    |}]

