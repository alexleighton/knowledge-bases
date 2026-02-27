(** Relation kind — a validated name for a relation type.

    Kind strings are lowercase alphanumeric with hyphens, 1–50 characters.
    Examples: ["depends-on"], ["related-to"], ["designed-by"]. *)

(** Abstract type of relation kinds. *)
type t

(** [make s] constructs a relation kind from [s].

    The string must be 1–50 characters, match [[a-z0-9][a-z0-9-]*],
    and not end with ['-'].

    @raise Invalid_argument if validation fails. *)
val make : string -> t

(** [parse s] parses [s] as a relation kind.
    @return [Error msg] if [s] is not a valid kind string. *)
val parse : string -> (t, string) result

(** [to_string t] returns the underlying kind string. *)
val to_string : t -> string

(** [equal a b] is [true] when [a] and [b] represent the same kind. *)
val equal : t -> t -> bool

(** [pp fmt t] pretty-prints the kind. *)
val pp : Format.formatter -> t -> unit

(** [show t] returns the string that {!pp} would print. *)
val show : t -> string
