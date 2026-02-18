(** Title type — a validated, non-empty string of at most 100 characters. *)

(** Abstract type of titles. *)
type t

(** [make s] constructs a [Title.t] from [s].

    - [s] must be non-empty and at most 100 characters.

    @raise Invalid_argument if validation fails. *)
val make : string -> t

(** [to_string t] returns the underlying string. *)
val to_string : t -> string

(** [pp fmt t] prints [t] using the formatter [fmt]. *)
val pp : Format.formatter -> t -> unit

(** [show t] returns the same string that {!pp} would print. *)
val show : t -> string
