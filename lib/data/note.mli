(** Note type and operations.

    A note bundles an [Identifier.t] with a title and content.
*)

(** Abstract type of notes. *)
type t

(** [pp fmt t] prints the note [t] using the formatter [fmt]. *)
val pp : Format.formatter -> t -> unit

(** [show t] returns the same string that {!pp} would print. *)
val show : t -> string

(** [make identifier title content] constructs a note after validating inputs.

    - [title] must be non-empty and at most 100 characters.
    - [content] must be non-empty and at most 10000 characters.

    @raise Invalid_argument if validation fails. *)
val make : Identifier.t -> string -> string -> t

(** [id t] returns the note identifier. *)
val id : t -> Identifier.t

(** [title t] returns the title of the note. *)
val title : t -> string

(** [content t] returns the content of the note. *)
val content : t -> string
