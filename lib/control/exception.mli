(** Exception helper functions.

    Provides a convenient way to raise [Invalid_argument] with formatted
    messages.
*)

(** [invalid_argf fmt ...] raises [Invalid_argument] with a message
    built from the format string [fmt] and its arguments.

    {[
      invalid_argf "expected %d, got %d" 10 42
      (* raises Invalid_argument "expected 10, got 42" *)
    ]}

    @raise Invalid_argument always raised with the formatted message
*)
val invalid_argf : ('a, unit, string, 'b) format4 -> 'a
