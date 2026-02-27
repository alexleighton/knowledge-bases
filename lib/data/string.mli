(** Extended string module.

    Includes all functions from {!Stdlib.String} plus additional utilities. *)

include module type of Stdlib.String

(** [contains_substring ~needle haystack] returns [true] if [needle] occurs
    anywhere inside [haystack]. *)
val contains_substring : needle:string -> string -> bool

(** [rsplit ~sep s] splits [s] at the last occurrence of character [sep].
    Returns [Some (left, right)] where [left] is everything before [sep]
    and [right] is everything after. Returns [None] if [sep] is not found. *)
val rsplit : sep:char -> string -> (string * string) option
