module Typeid = Kbases.Data.Uuid.Typeid

(* Helper to print of_string result *)
let print_parse_result str =
  try
    let tid = Typeid.of_string str in
    Printf.printf "Some(%s)\n" (Typeid.to_string tid)
  with
  | Invalid_argument msg -> Printf.printf "Invalid (%s, %s)\n" str msg

(* Valid test cases: (uuid_string, prefix, expected_typeid_string) *)
let valid_cases = [
  ("01890a5d-ac96-774b-bcce-b302099a8057", "prefix", "prefix_01h455vb4pex5vsknk084sn02q");
  ("0110c853-1d09-52d8-d73e-1194e95b5f19", "prefix", "prefix_0123456789abcdefghjkmnpqrs");
]

let bare_suffixes = [
  "00000000000000000000000000";
  "00000000000000000000000001";
  "0000000000000000000000000a";
  "0000000000000000000000000g";
  "00000000000000000000000010";
  "7zzzzzzzzzzzzzzzzzzzzzzzzz";
]

let%expect_test "valid parsing and roundtrip" =
  List.iter
    (fun (_uuid_str, _prefix, expected_typeid) ->
       (* Parse the expected typeid string *)
       let tid = Typeid.of_string expected_typeid in
       let roundtrip = Typeid.to_string tid in
       let got_prefix = Typeid.get_prefix tid in
       let got_suffix = Typeid.get_suffix tid in
       Printf.printf "(%s) prefix=%s suffix=%s roundtrip=%s\n"
         expected_typeid got_prefix got_suffix roundtrip)
    valid_cases;
  [%expect {|
    (prefix_01h455vb4pex5vsknk084sn02q) prefix=prefix suffix=01h455vb4pex5vsknk084sn02q roundtrip=prefix_01h455vb4pex5vsknk084sn02q
    (prefix_0123456789abcdefghjkmnpqrs) prefix=prefix suffix=0123456789abcdefghjkmnpqrs roundtrip=prefix_0123456789abcdefghjkmnpqrs
    |}]

let%expect_test "bare suffix parsing is rejected" =
  List.iter
    (fun suffix -> print_parse_result suffix)
    bare_suffixes;
  [%expect {|
    Invalid (00000000000000000000000000, Unable to determine prefix: 00000000000000000000000000)
    Invalid (00000000000000000000000001, Unable to determine prefix: 00000000000000000000000001)
    Invalid (0000000000000000000000000a, Unable to determine prefix: 0000000000000000000000000a)
    Invalid (0000000000000000000000000g, Unable to determine prefix: 0000000000000000000000000g)
    Invalid (00000000000000000000000010, Unable to determine prefix: 00000000000000000000000010)
    Invalid (7zzzzzzzzzzzzzzzzzzzzzzzzz, Unable to determine prefix: 7zzzzzzzzzzzzzzzzzzzzzzzzz)
    |}]

let%expect_test "parsing with underscore in prefix" =
  (* pr_efix_00000000000000000000000000 splits at last underscore *)
  let t = Typeid.of_string "pr_efix_00000000000000000000000000" in
  Printf.printf "prefix=%s suffix=%s\n" (Typeid.get_prefix t) (Typeid.get_suffix t);
  [%expect {|
    prefix=pr_efix suffix=00000000000000000000000000
    |}]

(* Invalid prefix test cases *)
let%expect_test "invalid prefix - uppercase" =
  print_parse_result "PREFIX_00000000000000000000000000";
  [%expect {| Invalid (PREFIX_00000000000000000000000000, Prefix may only contain lowercase ASCII letters or underscores) |}]

let%expect_test "invalid prefix - numeric" =
  print_parse_result "12345_00000000000000000000000000";
  [%expect {| Invalid (12345_00000000000000000000000000, Prefix may only contain lowercase ASCII letters or underscores) |}]

let%expect_test "invalid prefix - period" =
  print_parse_result "pre.fix_00000000000000000000000000";
  [%expect {| Invalid (pre.fix_00000000000000000000000000, Prefix may only contain lowercase ASCII letters or underscores) |}]

let%expect_test "invalid prefix - non-ascii" =
  print_parse_result "préfix_00000000000000000000000000";
  [%expect {| Invalid (préfix_00000000000000000000000000, Prefix may only contain lowercase ASCII letters or underscores) |}]

let%expect_test "invalid prefix - space" =
  print_parse_result " prefix_00000000000000000000000000";
  [%expect {| Invalid ( prefix_00000000000000000000000000, Prefix may only contain lowercase ASCII letters or underscores) |}]

let%expect_test "invalid prefix - too long (64 chars)" =
  print_parse_result
    "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl_00000000000000000000000000";
  [%expect {| Invalid (abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl_00000000000000000000000000, Prefix must be between 1 and 63 characters) |}]

let%expect_test "invalid - empty prefix with separator" =
  print_parse_result "_00000000000000000000000000";
  [%expect {| Invalid (_00000000000000000000000000, Prefix must be between 1 and 63 characters) |}]

let%expect_test "invalid - only separator" =
  print_parse_result "_";
  [%expect {| Invalid (_, Prefix must be between 1 and 63 characters) |}]

let%expect_test "invalid prefix - starts with underscore" =
  print_parse_result "_prefix_00000000000000000000000000";
  [%expect {| Invalid (_prefix_00000000000000000000000000, Prefix cannot start with _) |}]

let%expect_test "invalid prefix - ends with underscore" =
  print_parse_result "prefix__00000000000000000000000000";
  [%expect {| Invalid (prefix__00000000000000000000000000, Prefix cannot end with _) |}]

(* Invalid suffix test cases *)
let%expect_test "invalid suffix - too short (25 chars)" =
  print_parse_result "prefix_0000000000000000000000000";
  [%expect {| Invalid (prefix_0000000000000000000000000, Suffix must be 26 characters) |}]

let%expect_test "invalid suffix - too long (27 chars)" =
  print_parse_result "prefix_000000000000000000000000000";
  [%expect {| Invalid (prefix_000000000000000000000000000, Suffix must be 26 characters) |}]

let%expect_test "invalid suffix - space" =
  print_parse_result "prefix_1234567890123456789012345 ";
  [%expect {| Invalid (prefix_1234567890123456789012345 , Suffix must be base32) |}]

let%expect_test "invalid suffix - uppercase" =
  print_parse_result "prefix_0123456789ABCDEFGHJKMNPQRS";
  [%expect {| Invalid (prefix_0123456789ABCDEFGHJKMNPQRS, Suffix must be base32) |}]

let%expect_test "invalid suffix - hyphens" =
  print_parse_result "prefix_123456789-123456789-123456";
  [%expect {| Invalid (prefix_123456789-123456789-123456, Suffix must be base32) |}]

let%expect_test "invalid suffix - wrong alphabet (i, l, o, u)" =
  print_parse_result "prefix_ooooooiiiiiiuuuuuuulllllll";
  [%expect {| Invalid (prefix_ooooooiiiiiiuuuuuuulllllll, Suffix must be base32) |}]

let%expect_test "invalid suffix - ambiguous crockford chars" =
  print_parse_result "prefix_i23456789ol23456789oi23456";
  [%expect {| Invalid (prefix_i23456789ol23456789oi23456, Suffix must be base32) |}]

let%expect_test "invalid suffix - overflow (first char > 7)" =
  print_parse_result "prefix_8zzzzzzzzzzzzzzzzzzzzzzzzz";
  [%expect {| Invalid (prefix_8zzzzzzzzzzzzzzzzzzzzzzzzz, Int1128.of_string) |}]

let%expect_test "of_guid creates valid typeid" =
  let uuid_str = "01890a5d-ac96-774b-bcce-b302099a8057" in
  let uuid = Kbases.Data.Uuid.Uuidv7.of_string uuid_str in
  let tid = Typeid.of_guid "test" uuid in
  Printf.printf "prefix=%s suffix=%s to_string=%s\n"
    (Typeid.get_prefix tid)
    (Typeid.get_suffix tid)
    (Typeid.to_string tid);
  [%expect {|
    prefix=test suffix=01h455vb4pex5vsknk084sn02q to_string=test_01h455vb4pex5vsknk084sn02q
    |}]

