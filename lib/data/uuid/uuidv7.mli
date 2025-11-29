(** UUIDv7 generation and manipulation.

    UUIDv7 is a time-ordered UUID format that encodes a Unix timestamp
    in milliseconds along with random bits for uniqueness. *)

(** The type for UUIDv7 values. *)
type t

(** [make ()] creates a new random UUIDv7 using the current time. *)
val make : unit -> t

(** [to_uint128 uuid] converts a UUID to its 128-bit integer representation. *)
val to_uint128 : t -> Stdint.Uint128.t

(** [of_uint128 n] creates a UUID from a 128-bit integer. *)
val of_uint128 : Stdint.Uint128.t -> t

(** [to_uuidm uuid] converts the UUIDv7 to a [Uuidm.t] representation. *)
val to_uuidm : t -> Uuidm.t

(** [of_uuidm uuid] converts an existing [Uuidm.t] to a UUIDv7. *)
val of_uuidm : Uuidm.t -> t

(** [to_string uuid] returns the standard lowercase hyphenated UUID string
    representation (e.g. "01890a5d-ac96-774b-bcce-b302099a8057"). *)
val to_string : t -> string

(** [of_string s] parses a UUID from its string representation.
    The string should be in standard UUID format with or without hyphens.
    Parsing is case-insensitive.

    @raise Invalid_argument if the string is malformed. *)
val of_string : string -> t
