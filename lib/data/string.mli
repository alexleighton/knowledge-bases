(** Extended string module.

    Includes all functions from {!Stdlib.String} plus additional utilities. *)

    include module type of Stdlib.String

    (** [for_all pred s] returns [true] if all characters in [s] satisfy
        the predicate [pred]. Returns [true] for empty strings. *)
    val for_all : (char -> bool) -> string -> bool
    
    (** [rsplit ~sep s] splits [s] at the last occurrence of character [sep].
        Returns [Some (left, right)] where [left] is everything before [sep]
        and [right] is everything after. Returns [None] if [sep] is not found. *)
    val rsplit : sep:char -> string -> (string * string) option
