(** Namespace acronym generation utilities. *)

(**
  [of_name name] generates a lowercase acronym from [name] by taking the
  first letter of each word. Words are separated by hyphens, underscores,
  or spaces.
*)
val of_name : string -> string
