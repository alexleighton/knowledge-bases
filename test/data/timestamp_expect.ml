module Timestamp = Kbases.Data.Timestamp

let%expect_test "to_iso8601 formats known epochs" =
  let cases = [0; 1710000000; 1000000000; 86400] in
  List.iter (fun epoch ->
    Printf.printf "%d -> %s\n" epoch (Timestamp.to_iso8601 (Timestamp.make epoch))
  ) cases;
  [%expect {|
    0 -> 1970-01-01T00:00:00Z
    1710000000 -> 2024-03-09T16:00:00Z
    1000000000 -> 2001-09-09T01:46:40Z
    86400 -> 1970-01-02T00:00:00Z
  |}]

let%expect_test "of_iso8601 round-trip" =
  let epochs = [0; 1710000000; 1000000000; 86400; 1609459200] in
  List.iter (fun epoch ->
    let iso = Timestamp.to_iso8601 (Timestamp.make epoch) in
    match Timestamp.of_iso8601 iso with
    | Ok rt -> Printf.printf "%d -> %s -> %d (match=%b)\n" epoch iso (Timestamp.to_epoch rt) (Timestamp.to_epoch rt = epoch)
    | Error msg -> Printf.printf "%d -> %s -> ERROR: %s\n" epoch iso msg
  ) epochs;
  [%expect {|
    0 -> 1970-01-01T00:00:00Z -> 0 (match=true)
    1710000000 -> 2024-03-09T16:00:00Z -> 1710000000 (match=true)
    1000000000 -> 2001-09-09T01:46:40Z -> 1000000000 (match=true)
    86400 -> 1970-01-02T00:00:00Z -> 86400 (match=true)
    1609459200 -> 2021-01-01T00:00:00Z -> 1609459200 (match=true)
  |}]

let%expect_test "of_iso8601 rejects malformed input" =
  let bad_inputs = [
    "";
    "not-a-date";
    "2024-03-09";
    "2024-03-09 16:00:00Z";
  ] in
  List.iter (fun s ->
    match Timestamp.of_iso8601 s with
    | Ok n -> Printf.printf "%S -> unexpected Ok %d\n" s (Timestamp.to_epoch n)
    | Error msg -> Printf.printf "%S -> %s\n" s msg
  ) bad_inputs;
  [%expect {|
    "" -> Invalid ISO 8601 timestamp: ""
    "not-a-date" -> Invalid ISO 8601 timestamp: "not-a-date"
    "2024-03-09" -> Invalid ISO 8601 timestamp: "2024-03-09"
    "2024-03-09 16:00:00Z" -> Invalid ISO 8601 timestamp: "2024-03-09 16:00:00Z"
  |}]

let%expect_test "to_display formats known epochs" =
  let cases = [0; 1710000000; 1609459200] in
  List.iter (fun epoch ->
    Printf.printf "%d -> %s\n" epoch (Timestamp.to_display (Timestamp.make epoch))
  ) cases;
  [%expect {|
    0 -> 1970-01-01 00:00:00 UTC
    1710000000 -> 2024-03-09 16:00:00 UTC
    1609459200 -> 2021-01-01 00:00:00 UTC
  |}]
