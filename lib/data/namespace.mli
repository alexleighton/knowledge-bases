(** Namespace acronym generation utilities. *)

type t

(**
  [validate ns] validates that [ns] is 1-5 lowercase ASCII letters.
  Returns [Ok ns] when valid, or [Error msg] when invalid.
*)
val validate : string -> (t, string) result

(** [of_string ns] validates and constructs a namespace.
    @raise Invalid_argument when [ns] is invalid. *)
val of_string : string -> t

(** [to_string t] returns the namespace value as a string. *)
val to_string : t -> string

(**
  [of_name name] generates a lowercase acronym from [name] by taking the
  first letter of each word. Words are separated by hyphens, underscores,
  or spaces.
*)
val of_name : string -> string
