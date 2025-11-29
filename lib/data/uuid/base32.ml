open Stdint

module CE = Control.Exception

let bits_per_char = 5
let normalized_bit_length = 130
let uuid_byte_length = 16
let encoded_length = normalized_bit_length / bits_per_char

let encode_char = function
  |  0 -> '0' |  1 -> '1' |  2 -> '2' |  3 -> '3'
  |  4 -> '4' |  5 -> '5' |  6 -> '6' |  7 -> '7'
  |  8 -> '8' |  9 -> '9' | 10 -> 'a' | 11 -> 'b'
  | 12 -> 'c' | 13 -> 'd' | 14 -> 'e' | 15 -> 'f'
  | 16 -> 'g' | 17 -> 'h' | 18 -> 'j' | 19 -> 'k'
  | 20 -> 'm' | 21 -> 'n' | 22 -> 'p' | 23 -> 'q'
  | 24 -> 'r' | 25 -> 's' | 26 -> 't' | 27 -> 'v'
  | 28 -> 'w' | 29 -> 'x' | 30 -> 'y' | 31 -> 'z'
  | _ -> invalid_arg "Invalid argument, should be between 0 and 31"

let decode_char c =
  match Char.lowercase_ascii c with
  | '0' -> "00000" | '1' -> "00001" | '2' -> "00010" | '3' -> "00011"
  | '4' -> "00100" | '5' -> "00101" | '6' -> "00110" | '7' -> "00111"
  | '8' -> "01000" | '9' -> "01001" | 'a' -> "01010" | 'b' -> "01011"
  | 'c' -> "01100" | 'd' -> "01101" | 'e' -> "01110" | 'f' -> "01111"
  | 'g' -> "10000" | 'h' -> "10001" | 'j' -> "10010" | 'k' -> "10011"
  | 'm' -> "10100" | 'n' -> "10101" | 'p' -> "10110" | 'q' -> "10111"
  | 'r' -> "11000" | 's' -> "11001" | 't' -> "11010" | 'v' -> "11011"
  | 'w' -> "11100" | 'x' -> "11101" | 'y' -> "11110" | 'z' -> "11111"
  | _ -> CE.invalid_arg1 "Invalid character '%c'" c

let is_valid_char = function
  | '0'..'9' | 'a'..'h' | 'j' | 'k' | 'm' | 'n' | 'p'..'t' | 'v'..'z' -> true
  | _ -> false

let encode uuid =
  (* Convert UUID → 26-char Crockford Base32. We walk the value from the
     least-significant end, 5 bits at a time, filling the output buffer
     right-to-left. *)
  let uuid_bytes = Bytes.of_string (Uuidm.to_binary_string uuid) in
  let uint128 = Uint128.of_bytes_big_endian uuid_bytes 0 in
  let mask5 = Uint128.of_int 31 in (* 0b11111 *)
  let res = Bytes.make encoded_length '\000' in
  let v = ref uint128 in
  (* Write digits from least-significant-bits towards most-significant-bits *)
  for idx = encoded_length - 1 downto 1 do
    let c_val = Uint128.(to_int (logand !v mask5)) in
    Bytes.set res idx (encode_char c_val);
    v := Uint128.shift_right !v bits_per_char;
  done;
  (* Final digit: encodes the top 3 data bits; the leading 2 bits of this
     5-bit chunk are always zero padding. *)
  let top3 = (Uint128.to_int !v) land 0b111 in
  Bytes.set res 0 (encode_char top3);
  Bytes.to_string res

let decode encoded =
  (* 26-char Base32 → UUID. Expand each digit into 5 bits, rebuild the
     128-bit value, then convert to UUID. *)
  let len = String.length encoded in
  if len <> encoded_length then
    invalid_arg
      (Printf.sprintf "Invalid base32 length: expected %d, got %d"
         encoded_length len);
  let bits = Buffer.create normalized_bit_length in
  String.iter (fun c -> Buffer.add_string bits (decode_char c)) encoded;
  let binary_string = Buffer.contents bits in
  let uint128 = Uint128.of_string ("0b" ^ binary_string) in
  let bytes = Bytes.make uuid_byte_length '\000' in
  Uint128.to_bytes_big_endian uint128 bytes 0;
  match Uuidm.of_binary_string (Bytes.to_string bytes) with
  | Some uuid -> uuid
  | None -> invalid_arg "Invalid UUID binary representation"
