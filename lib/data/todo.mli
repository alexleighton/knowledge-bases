(** Todo type and operations.

    A todo pairs a note with a workflow status. The status can be [Open],
    [In_Progress], or [Done].
*)

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

(** [make note status] constructs a todo from [note] and [status]. *)
val make : Note.t -> status -> t

(** [note t] returns the note component. *)
val note : t -> Note.t

(** [status t] returns the status component. *)
val status : t -> status

(** [id t] returns the identifier of the note within the todo. *)
val id : t -> Identifier.t
