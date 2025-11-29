(** Extended character module.

    Includes all functions from {!Stdlib.Char} plus additional predicates. *)

include module type of Stdlib.Char

(** [is_lowercase c] returns [true] if [c] is a lowercase ASCII letter
    (['a'..'z']). *)
val is_lowercase : char -> bool

(** [is_uppercase c] returns [true] if [c] is an uppercase ASCII letter
    (['A'..'Z']). *)
val is_uppercase : char -> bool

(** [is_letter c] returns [true] if [c] is an ASCII letter
    (['a'..'z'] or ['A'..'Z']). *)
val is_letter : char -> bool

(** [is_digit c] returns [true] if [c] is an ASCII digit (['0'..'9']). *)
val is_digit : char -> bool

(** [is_hex_digit c] returns [true] if [c] is a hexadecimal digit
    (['0'..'9'], ['a'..'f'], or ['A'..'F']). *)
val is_hex_digit : char -> bool
    