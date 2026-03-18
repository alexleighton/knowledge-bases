(** Todo type and operations.

    A todo is a self-contained entity with its own TypeId, a human-friendly
    identifier, a title, content, and a workflow status. The status can be
    [Open], [In_Progress], or [Done].
*)

(** Unique TypeId for todos. *)
type id = Uuid.Typeid.t

(** [make_id ()] generates a fresh todo TypeId. *)
val make_id : unit -> id

(** Status of a todo item. *)
type status = Open | In_Progress | Done

(** Abstract type of todos. *)
type t

(** [pp fmt t] prints the todo [t] using the formatter [fmt]. *)
val pp : Format.formatter -> t -> unit

(** [show t] returns the same string that {!pp} would print. *)
val show : t -> string

(** [status_to_string status] returns the string representation of the status. *)
val status_to_string : status -> string

(** [status_from_string s] parses [s] as a status.

    Accepts the strings ["open"], ["in-progress"], and ["done"].

    @raise Invalid_argument if parsing fails. *)
val status_from_string : string -> status

(** [status_of_string s] parses [s] as a status.
    @return [Error msg] if [s] is not a recognised status string. *)
val status_of_string : string -> (status, string) result

(** [make id niceid title content status ~created_at ~updated_at] constructs a todo
    from already-validated inputs.

    @raise Invalid_argument if the [id] does not carry the ["todo"] TypeId prefix. *)
val make : id -> Identifier.t -> Title.t -> Content.t -> status -> created_at:Timestamp.t -> updated_at:Timestamp.t -> t

(** [id t] returns the todo TypeId. *)
val id : t -> id

(** [niceid t] returns the human-friendly identifier. *)
val niceid : t -> Identifier.t

(** [title t] returns the title of the todo. *)
val title : t -> Title.t

(** [content t] returns the content of the todo. *)
val content : t -> Content.t

(** [status t] returns the status of the todo. *)
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
