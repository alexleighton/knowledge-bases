(** Note type and operations.

    A note bundles a stable TypeId along with a secondary [Identifier.t],
    referred to as a "nice id", plus a title and content. *)

(** Unique TypeId for notes. *)
type id = Uuid.Typeid.t

(** [make_id ()] generates a fresh note TypeId. *)
val make_id : unit -> id

(** Abstract type of notes. *)
type t

(** [pp fmt t] prints the note [t] using the formatter [fmt]. *)
val pp : Format.formatter -> t -> unit

(** [show t] returns the same string that {!pp} would print. *)
val show : t -> string

(** [make id niceid title content] constructs a note after validating inputs.

    - [title] must be non-empty and at most 100 characters.
    - [content] must be non-empty and at most 10000 characters.

    @raise Invalid_argument if validation fails. *)
val make : id -> Identifier.t -> string -> string -> t

(** [id t] returns the note TypeId. *)
val id : t -> id

(** [niceid t] returns the human-friendly identifier. *)
val niceid : t -> Identifier.t

(** [title t] returns the title of the note. *)
val title : t -> string

(** [content t] returns the content of the note. *)
val content : t -> string
