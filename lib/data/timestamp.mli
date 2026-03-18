(** Timestamps as Unix epoch seconds.

    Timestamps are represented as an abstract [t] throughout the domain.
    This module validates on construction (non-negative epoch), converts
    to and from human-readable formats at serialisation boundaries, and
    provides ordering. *)

(** An epoch-seconds timestamp.  Always >= 0. *)
type t

(** [make epoch] wraps [epoch] as a timestamp.

    @raise Invalid_argument if [epoch] is negative. *)
val make : int -> t

(** [now ()] returns the current time as a timestamp. *)
val now : unit -> t

(** [to_epoch t] returns the underlying epoch seconds. *)
val to_epoch : t -> int

(** [compare a b] orders timestamps by epoch seconds. *)
val compare : t -> t -> int

(** [to_iso8601 t] formats [t] as ["YYYY-MM-DDTHH:MM:SSZ"]. *)
val to_iso8601 : t -> string

(** [of_iso8601 s] parses an ISO 8601 string ["YYYY-MM-DDTHH:MM:SSZ"]
    to a timestamp.

    @return [Error msg] if [s] is not in the expected format. *)
val of_iso8601 : string -> (t, string) result

(** [to_display t] formats [t] as ["YYYY-MM-DD HH:MM:SS UTC"]
    for text output. *)
val to_display : t -> string

(** [pp fmt t] pretty-prints the timestamp as its epoch integer. *)
val pp : Format.formatter -> t -> unit

(** [show t] returns the epoch integer as a string. *)
val show : t -> string
