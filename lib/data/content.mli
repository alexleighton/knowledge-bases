(** Content type — a validated, non-empty string of at most 10 000 characters. *)

(** Abstract type of content. *)
type t

(** [make s] constructs a [Content.t] from [s].

    - [s] must be non-empty and at most 10 000 characters.

    @raise Invalid_argument if validation fails. *)
val make : string -> t

(** [to_string t] returns the underlying string. *)
val to_string : t -> string

(** [pp fmt t] prints [t] using the formatter [fmt]. *)
val pp : Format.formatter -> t -> unit

(** [show t] returns the same string that {!pp} would print. *)
val show : t -> string
