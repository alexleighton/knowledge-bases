module Uuidv7 = Kbases.Data.Uuid.Uuidv7

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
]

let%expect_test "string roundtrip cases" =
  List.iter
    (fun (label, input) ->
       let uuid = Uuidv7.of_string input in
       let from_upper = Uuidv7.of_string (String.uppercase_ascii input) in
       let via_uint128 = Uuidv7.(of_uint128 (to_uint128 uuid)) in
       Printf.printf "(%s)\n  %s (input)\n  %s (roundtrip)\n  %s (upper roundtrip)\n  %s (uint128 roundtrip)\n"
         label input
         (Uuidv7.to_string uuid)
         (Uuidv7.to_string from_upper)
         (Uuidv7.to_string via_uint128))
    cases;
  [%expect {|
    (sample-1)
      a9f81698-6a94-416e-8e2c-907e2ee0c334 (input)
      a9f81698-6a94-416e-8e2c-907e2ee0c334 (roundtrip)
      a9f81698-6a94-416e-8e2c-907e2ee0c334 (upper roundtrip)
      a9f81698-6a94-416e-8e2c-907e2ee0c334 (uint128 roundtrip)
    (sample-2)
      4a79c331-2335-4235-87c1-839c984cec44 (input)
      4a79c331-2335-4235-87c1-839c984cec44 (roundtrip)
      4a79c331-2335-4235-87c1-839c984cec44 (upper roundtrip)
      4a79c331-2335-4235-87c1-839c984cec44 (uint128 roundtrip)
    (sample-3)
      68ebd5aa-9c38-4db0-bdfb-157eeb9f8082 (input)
      68ebd5aa-9c38-4db0-bdfb-157eeb9f8082 (roundtrip)
      68ebd5aa-9c38-4db0-bdfb-157eeb9f8082 (upper roundtrip)
      68ebd5aa-9c38-4db0-bdfb-157eeb9f8082 (uint128 roundtrip)
    (sample-4)
      33cf25d3-aa82-46ff-83bb-a18968d5b2ee (input)
      33cf25d3-aa82-46ff-83bb-a18968d5b2ee (roundtrip)
      33cf25d3-aa82-46ff-83bb-a18968d5b2ee (upper roundtrip)
      33cf25d3-aa82-46ff-83bb-a18968d5b2ee (uint128 roundtrip)
    (sample-5)
      8938998e-d6e9-41c3-a035-04131f67a2be (input)
      8938998e-d6e9-41c3-a035-04131f67a2be (roundtrip)
      8938998e-d6e9-41c3-a035-04131f67a2be (upper roundtrip)
      8938998e-d6e9-41c3-a035-04131f67a2be (uint128 roundtrip)
    (nil)
      00000000-0000-0000-0000-000000000000 (input)
      00000000-0000-0000-0000-000000000000 (roundtrip)
      00000000-0000-0000-0000-000000000000 (upper roundtrip)
      00000000-0000-0000-0000-000000000000 (uint128 roundtrip)
    (max)
      ffffffff-ffff-ffff-ffff-ffffffffffff (input)
      ffffffff-ffff-ffff-ffff-ffffffffffff (roundtrip)
      ffffffff-ffff-ffff-ffff-ffffffffffff (upper roundtrip)
      ffffffff-ffff-ffff-ffff-ffffffffffff (uint128 roundtrip)
    (valid-test)
      01890a5d-ac96-774b-bcce-b302099a8057 (input)
      01890a5d-ac96-774b-bcce-b302099a8057 (roundtrip)
      01890a5d-ac96-774b-bcce-b302099a8057 (upper roundtrip)
      01890a5d-ac96-774b-bcce-b302099a8057 (uint128 roundtrip)
    (valid-alphabet)
      0110c853-1d09-52d8-d73e-1194e95b5f19 (input)
      0110c853-1d09-52d8-d73e-1194e95b5f19 (roundtrip)
      0110c853-1d09-52d8-d73e-1194e95b5f19 (upper roundtrip)
      0110c853-1d09-52d8-d73e-1194e95b5f19 (uint128 roundtrip)
    |}]

let%expect_test "decode invalid inputs" =
  let invalid_inputs = [
    ("invalid-char", "00000000-0000-0000-0000-00000000000I");
    ("invalid-length", "abc");
  ] in
  List.iter
    (fun (label, input) ->
       try Uuidv7.of_string input |> ignore with
       | Invalid_argument msg -> Printf.printf "ERR(%s): %s\n" label msg)
    invalid_inputs;
  [%expect {|
    ERR(invalid-char): Invalid hex character 'i' in UUID string
    ERR(invalid-length): Invalid UUID hex length: expected 32, got 3
    |}]

