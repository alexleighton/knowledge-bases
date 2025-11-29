include Stdlib.Char

let is_lowercase c = c >= 'a' && c <= 'z'

let is_uppercase c = c >= 'A' && c <= 'Z'

let is_letter c = is_lowercase c || is_uppercase c

let is_digit c = c >= '0' && c <= '9'

let is_hex_digit c =
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
