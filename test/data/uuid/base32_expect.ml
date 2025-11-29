module Base32 = Kbases.Data.Uuid.Base32

let uuid_of_string_exn s =
  match Uuidm.of_string s with
  | Some uuid -> uuid
  | None -> failwith "invalid UUID literal"

let%expect_test "roundtrip cases" =
  let cases = [
    ("sample-1",       "a9f81698-6a94-416e-8e2c-907e2ee0c334");
    ("sample-2",       "4a79c331-2335-4235-87c1-839c984cec44");
    ("sample-3",       "68ebd5aa-9c38-4db0-bdfb-157eeb9f8082");
    ("sample-4",       "33cf25d3-aa82-46ff-83bb-a18968d5b2ee");
    ("sample-5",       "8938998e-d6e9-41c3-a035-04131f67a2be");
    ("nil",            Uuidm.to_string Uuidm.nil);
    ("max",            Uuidm.to_string Uuidm.max);
    ("valid-test",     "01890a5d-ac96-774b-bcce-b302099a8057");
    ("valid-alphabet", "0110c853-1d09-52d8-d73e-1194e95b5f19");
  ] in
  List.iter
    (fun (label, input) ->
      let uuid = uuid_of_string_exn input in
      let encoded = Base32.encode uuid in
      let decoded = Base32.decode encoded in
      let decoded_upper = Base32.decode (String.uppercase_ascii encoded) in
      Printf.printf "(%s) %s\n  %s (input)\n  %s (roundtrip)\n  %s (upper roundtrip)\n" label encoded input (Uuidm.to_string decoded) (Uuidm.to_string decoded_upper)
    )cases;
  [%expect {|
    (sample-1) 59z0b9gtmm85q8wb4gfrqe1gsm
      a9f81698-6a94-416e-8e2c-907e2ee0c334 (input)
      a9f81698-6a94-416e-8e2c-907e2ee0c334 (roundtrip)
      a9f81698-6a94-416e-8e2c-907e2ee0c334 (upper roundtrip)
    (sample-2) 2af71k28sn88trfgc3kjc4sv24
      4a79c331-2335-4235-87c1-839c984cec44 (input)
      4a79c331-2335-4235-87c1-839c984cec44 (roundtrip)
      4a79c331-2335-4235-87c1-839c984cec44 (upper roundtrip)
    (sample-3) 38xfatn71r9prbvyrnfvnsz042
      68ebd5aa-9c38-4db0-bdfb-157eeb9f8082 (input)
      68ebd5aa-9c38-4db0-bdfb-157eeb9f8082 (roundtrip)
      68ebd5aa-9c38-4db0-bdfb-157eeb9f8082 (upper roundtrip)
    (sample-4) 1kswjx7am28vzr7ex1h5mdbcqe
      33cf25d3-aa82-46ff-83bb-a18968d5b2ee (input)
      33cf25d3-aa82-46ff-83bb-a18968d5b2ee (roundtrip)
      33cf25d3-aa82-46ff-83bb-a18968d5b2ee (upper roundtrip)
    (sample-5) 4972crxnq9871t0d842cfpf8ny
      8938998e-d6e9-41c3-a035-04131f67a2be (input)
      8938998e-d6e9-41c3-a035-04131f67a2be (roundtrip)
      8938998e-d6e9-41c3-a035-04131f67a2be (upper roundtrip)
    (nil) 00000000000000000000000000
      00000000-0000-0000-0000-000000000000 (input)
      00000000-0000-0000-0000-000000000000 (roundtrip)
      00000000-0000-0000-0000-000000000000 (upper roundtrip)
    (max) 7zzzzzzzzzzzzzzzzzzzzzzzzz
      ffffffff-ffff-ffff-ffff-ffffffffffff (input)
      ffffffff-ffff-ffff-ffff-ffffffffffff (roundtrip)
      ffffffff-ffff-ffff-ffff-ffffffffffff (upper roundtrip)
    (valid-test) 01h455vb4pex5vsknk084sn02q
      01890a5d-ac96-774b-bcce-b302099a8057 (input)
      01890a5d-ac96-774b-bcce-b302099a8057 (roundtrip)
      01890a5d-ac96-774b-bcce-b302099a8057 (upper roundtrip)
    (valid-alphabet) 0123456789abcdefghjkmnpqrs
      0110c853-1d09-52d8-d73e-1194e95b5f19 (input)
      0110c853-1d09-52d8-d73e-1194e95b5f19 (roundtrip)
      0110c853-1d09-52d8-d73e-1194e95b5f19 (upper roundtrip)
    |}]

let%expect_test "decode invalid inputs" =
  let invalid_inputs = [
    ("invalid-char", "0000000000000000000000000I");
    ("invalid-length", "abc");
  ] in
  List.iter
    (fun (label, input) ->
      try Base32.decode input |> ignore with 
      |Invalid_argument msg -> Printf.printf "ERR(%s): %s\n" label msg)
    invalid_inputs;
  [%expect {|
    ERR(invalid-char): Invalid character 'I'
    ERR(invalid-length): Invalid base32 length: expected 26, got 3
    |}]

