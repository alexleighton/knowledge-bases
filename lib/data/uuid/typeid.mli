(** TypeId: Type-safe, K-sortable, globally unique identifiers.

    A TypeId combines a type prefix with a UUIDv7 encoded in Crockford Base32.
    The format is [prefix_suffix] where prefix identifies the type and suffix
    is the 26-character Base32 encoding of a UUIDv7. *)

(** Abstract type representing a TypeId. *)
type t

(** [make prefix] creates a new TypeId with the given prefix and a freshly
    generated UUIDv7.

    @raise Failure if [prefix] is invalid. A valid prefix:
    - Must be non-empty
    - Must contain only lowercase letters and underscores
    - Cannot start or end with an underscore
    - Must be at most 63 characters long *)
val make : string -> t

(** [to_string t] converts a TypeId to its string representation.
    Returns [suffix] if prefix is empty, otherwise [prefix_suffix]. *)
val to_string : t -> string

(** [of_string s] parses a string as a TypeId.
    @raise Invalid_argument if the string is invalid. *)
val of_string : string -> t

(** [of_guid prefix uuid] creates a TypeId from a prefix and existing UUID. *)
val of_guid : string -> Uuidv7.t -> t

(** [get_uuid t] returns the underlying UUID of the TypeId. *)
val get_uuid : t -> Uuidv7.t

(** [get_prefix t] returns the prefix of the TypeId. *)
val get_prefix : t -> string

(** [get_suffix t] returns the Base32-encoded suffix of the TypeId. *)
val get_suffix : t -> string
