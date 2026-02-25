(** Note type and operations.

    A note bundles a stable TypeId along with a secondary [Identifier.t],
    referred to as a "nice id", plus a title and content. *)

(** Unique TypeId for notes. *)
type id = Uuid.Typeid.t

(** [make_id ()] generates a fresh note TypeId. *)
val make_id : unit -> id

(** Status of a note. *)
type status = Active | Archived

(** Abstract type of notes. *)
type t

(** [pp fmt t] prints the note [t] using the formatter [fmt]. *)
val pp : Format.formatter -> t -> unit

(** [show t] returns the same string that {!pp} would print. *)
val show : t -> string

(** [status_to_string status] returns the string representation of the status. *)
val status_to_string : status -> string

(** [status_from_string s] parses [s] as a status.

    Accepts the strings ["active"] and ["archived"].

    @raise Invalid_argument if parsing fails. *)
val status_from_string : string -> status

(** [make id niceid title content status] constructs a note from already-validated inputs.

    @raise Invalid_argument if the [id] does not carry the ["note"] TypeId prefix. *)
val make : id -> Identifier.t -> Title.t -> Content.t -> status -> t

(** [id t] returns the note TypeId. *)
val id : t -> id

(** [niceid t] returns the human-friendly identifier. *)
val niceid : t -> Identifier.t

(** [title t] returns the title of the note. *)
val title : t -> Title.t

(** [content t] returns the content of the note. *)
val content : t -> Content.t

(** [status t] returns the status of the note. *)
val status : t -> status
