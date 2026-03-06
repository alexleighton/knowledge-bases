module Niceid = Kbases.Repository.Niceid
module Typeid = Kbases.Data.Uuid.Typeid
module Identifier = Kbases.Data.Identifier

let with_db = Test_helpers.with_db

let unwrap = function
  | Ok v -> v
  | Error (Niceid.Backend_failure msg) -> failwith ("backend failure: " ^ msg)

let%expect_test "allocate increments from zero" =
  with_db (fun db ->
    let repo = unwrap (Niceid.init ~db ~namespace:"nt") in
    let tid1 = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
    let tid2 = Typeid.of_string "note_0123456789abcdefghjkmnpqrt" in
    let print_result tid =
      match Niceid.allocate repo tid with
      | Ok ident -> Printf.printf "%s -> %d\n" (Typeid.to_string tid) (Identifier.raw_id ident)
      | Error (Niceid.Backend_failure msg) -> Printf.printf "alloc error: %s\n" msg
    in
    print_result tid1;
    print_result tid2);
  [%expect {|
    note_0123456789abcdefghjkmnpqrs -> 0
    note_0123456789abcdefghjkmnpqrt -> 1
    |}]

let%expect_test "delete_all clears all niceids and resets sequence" =
  with_db (fun db ->
    let repo = unwrap (Niceid.init ~db ~namespace:"nt") in
    let tid1 = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
    let tid2 = Typeid.of_string "note_0123456789abcdefghjkmnpqrt" in
    ignore (unwrap (Niceid.allocate repo tid1));
    ignore (unwrap (Niceid.allocate repo tid2));
    let () = unwrap (Niceid.delete_all repo) in
    let tid3 = Typeid.of_string "note_0123456789abcdefghjkmnpqrv" in
    (match Niceid.allocate repo tid3 with
     | Ok ident -> Printf.printf "after delete_all: %d\n" (Identifier.raw_id ident)
     | Error (Niceid.Backend_failure msg) -> Printf.printf "alloc error: %s\n" msg));
  [%expect {|
    after delete_all: 0
    |}]
