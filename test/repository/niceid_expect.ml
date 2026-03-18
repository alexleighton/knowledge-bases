module Niceid = Kbases.Repository.Niceid
module Typeid = Kbases.Data.Uuid.Typeid
module Identifier = Kbases.Data.Identifier

let with_db = Test_helpers.with_db

let unwrap = function
  | Ok v -> v
  | Error Niceid.Not_found -> failwith "not found"
  | Error (Niceid.Backend_failure msg) -> failwith ("backend failure: " ^ msg)

let pp_error = function
  | Niceid.Not_found -> print_endline "error: not found"
  | Niceid.Backend_failure msg -> Printf.printf "error: backend failure: %s\n" msg

let%expect_test "allocate increments from zero" =
  with_db (fun db ->
    let repo = unwrap (Niceid.init ~db ~namespace:"nt") in
    let tid1 = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
    let tid2 = Typeid.of_string "note_0123456789abcdefghjkmnpqrt" in
    let print_result tid =
      match Niceid.allocate repo tid with
      | Ok ident -> Printf.printf "%s -> %d\n" (Typeid.to_string tid) (Identifier.raw_id ident)
      | Error err -> pp_error err
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
     | Error (Niceid.Backend_failure msg) -> Printf.printf "alloc error: %s\n" msg
     | Error Niceid.Not_found -> Printf.printf "alloc error: not found\n"));
  [%expect {|
    after delete_all: 0
    |}]

let%expect_test "delete niceid then new allocation does not conflict" =
  with_db (fun db ->
    let repo = unwrap (Niceid.init ~db ~namespace:"nt") in
    let tid1 = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
    let tid2 = Typeid.of_string "note_0123456789abcdefghjkmnpqrt" in
    let id1 = unwrap (Niceid.allocate repo tid1) in
    ignore (unwrap (Niceid.allocate repo tid2));
    Printf.printf "before delete: tid1=%d\n" (Identifier.raw_id id1);
    (match Niceid.delete repo tid1 with
     | Ok () -> print_endline "delete ok"
     | Error err -> pp_error err);
    (* Re-allocate with a new typeid — should get next sequential id *)
    let tid3 = Typeid.of_string "note_0123456789abcdefghjkmnpqrv" in
    (match Niceid.allocate repo tid3 with
     | Ok ident -> Printf.printf "new allocation: %d\n" (Identifier.raw_id ident)
     | Error err -> pp_error err));
  [%expect {|
    before delete: tid1=0
    delete ok
    new allocation: 2
    |}]

let%expect_test "delete non-existent typeid returns Not_found" =
  with_db (fun db ->
    let repo = unwrap (Niceid.init ~db ~namespace:"nt") in
    let tid = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
    match Niceid.delete repo tid with
    | Ok () -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| error: not found |}]
