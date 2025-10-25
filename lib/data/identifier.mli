(** Identifier type and operations.

    An identifier is composed of a [namespace] and a non-negative [raw_id].
    The string form is ["<namespace>-<raw_id>"] (e.g., ["abc-123"]).
*)

(** Abstract type of identifiers. *)
 type t

(** [make namespace raw_id] constructs an identifier after validating inputs.
    
    - [namespace] must be 1–4 lowercase English letters ([a–z]).
    - [raw_id] must be [>= 0].
    
    @raise Invalid_argument if validation fails. *)
val make : string -> int -> t

(** [namespace t] returns the namespace component. *)
val namespace : t -> string

(** [raw_id t] returns the numeric id component. *)
val raw_id : t -> int

(** [to_string t] returns the canonical string representation ["<namespace>-<raw_id>"]. *)
val to_string : t -> string

(** [from_string s] parses [s] in the form ["<namespace>-<raw_id>"] and returns
    the corresponding identifier.
    
    The same validations as {!make} apply to the parsed components.
    
    @raise Invalid_argument if [s] is not of the expected form or if
    validations fail. *)
val from_string : string -> t

(** Pretty-printer for identifiers, prints as ["<namespace>-<raw_id>"]. *)
val pp : Format.formatter -> t -> unit
