(** Exception helper functions.

    These functions provide convenient ways to create formatted
    [Invalid_argument] exceptions.
*)

(** [invalid_arg1 fmt arg] creates an [Invalid_argument] exception with a
    formatted message.

    @param fmt the format string template
    @param arg the argument to substitute into the format string
    @raise Invalid_argument always raised with the formatted message
*)
val invalid_arg1 : ('a -> string, unit, string) format -> 'a -> 'b

(** [invalid_arg2 fmt arg1 arg2] creates an [Invalid_argument] exception with a
    formatted message.

    @param fmt the format string template
    @param arg1 the first argument to substitute into the format string
    @param arg2 the second argument to substitute into the format string
    @raise Invalid_argument always raised with the formatted message
*)
val invalid_arg2 : ('a -> 'b -> string, unit, string) format -> 'a -> 'b -> 'c
