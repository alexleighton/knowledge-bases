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

(** [status_of_string s] parses [s] as a status.
    @return [Error msg] if [s] is not a recognised status string. *)
val status_of_string : string -> (status, string) result

(** [make id niceid title content status ~created_at ~updated_at] constructs a note
    from already-validated inputs.

    @raise Invalid_argument if the [id] does not carry the ["note"] TypeId prefix. *)
val make : id -> Identifier.t -> Title.t -> Content.t -> status -> created_at:Timestamp.t -> updated_at:Timestamp.t -> t

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

(** [with_status t status] returns a copy of [t] with [status] replaced. *)
val with_status : t -> status -> t

(** [with_title t title] returns a copy of [t] with [title] replaced. *)
val with_title : t -> Title.t -> t

(** [with_content t content] returns a copy of [t] with [content] replaced. *)
val with_content : t -> Content.t -> t

(** [created_at t] returns the creation timestamp. *)
val created_at : t -> Timestamp.t

(** [updated_at t] returns the last-updated timestamp. *)
val updated_at : t -> Timestamp.t

(** [with_updated_at t ts] returns a copy of [t] with [updated_at] set to [ts]. *)
val with_updated_at : t -> Timestamp.t -> t
