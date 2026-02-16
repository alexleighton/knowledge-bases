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

(** [requiref condition fmt ...] validates that [condition] holds,
    raising [Invalid_argument] with a formatted message on failure.

    {[
      requiref (x >= 0) "expected non-negative, got %d" x
    ]}

    @raise Invalid_argument if [condition] is [false]
*)
val requiref : bool -> ('a, unit, string, unit) format4 -> 'a

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
