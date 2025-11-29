(** Base32 encoding helpers for UUIDs.

    Strings produced by this module use the Crockford alphabet, are always
    26 characters long and omit padding. *)

val encode : Uuidm.t -> string
(** [encode uuid] returns the 26-character, lowercase Base32 encoding of [uuid]
    using the Crockford alphabet (digits [0-9] and letters [a-z] without
    [i], [l], [o] and [u]). *)

val decode : string -> Uuidm.t
(** [decode encoded] parses [encoded] (case-insensitive Crockford alphabet)
    as the Base32 format produced by {!encode}. Raises [Invalid_argument] if
    [encoded] is malformed. *)

val is_valid_char : char -> bool
(** [is_valid_char c] is [true] when [c] belongs to the Crockford alphabet
    variant accepted by this module (digits [0-9], lowercase letters excluding
    [i], [l], [o], [u]). *)
