(** Assertion helper functions.

    These functions provide convenient ways to validate conditions.
*)

(** [require ?msg condition] validates that [condition] holds.

    If [condition] is [true], the function succeeds silently.
    If [condition] is [false], raises [Invalid_argument] with the given message.

    @param msg optional custom error message (default: "Requirement not met")
    @param condition the boolean condition to validate
    @raise Invalid_argument if [condition] is [false]
*)
val require : ?msg:string -> bool -> unit

(** [require1 ?msg ?arg condition] validates that [condition] holds with
    formatted error messages.

    If [condition] is [true], the function succeeds silently.
    If [condition] is [false], raises [Invalid_argument] with a formatted
    message.

    @param msg optional format string for the error message
    @param arg optional argument to substitute into the format string
    @param condition the boolean condition to validate
    @raise Invalid_argument if [condition] is [false]
*)
val require1 : ?msg:('a -> string, unit, string) format -> ?arg:'a -> bool -> unit

(** [require2 ?msg ?arg1 ?arg2 predicate] validates that [predicate] holds with
    formatted error messages.

    If [predicate] is [true], the function succeeds silently.
    If [predicate] is [false], raises [Invalid_argument] with a formatted
    message.

    @param msg optional format string for the error message
    @param arg1 optional first argument to substitute into the format string
    @param arg2 optional second argument to substitute into the format string
    @param predicate the boolean predicate to validate
    @raise Invalid_argument if [predicate] is [false]
*)
val require2 : ?msg:('a -> 'b -> string, unit, string) format
               -> ?arg1:'a -> ?arg2:'b -> bool -> unit

(** [require_strlen ?msg ~min ~max value] validates that the length of
    [value] lies within the inclusive range [[min], [max]].

    @param msg optional custom error message (default includes the offending
               length)
    @param min minimum accepted length
    @param max maximum accepted length
    @param value the string whose length is validated
    @raise Invalid_argument if the length is outside the inclusive range
*)
val require_strlen : ?msg:string -> min:int -> max:int -> string -> unit
