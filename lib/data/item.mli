(** Unified item type spanning todos and notes.

    This module provides the sum type and pure accessors shared by all
    service-layer modules that operate on both entity types. *)

(** An item is either a todo or a note. *)
type t =
  | Todo_item of Todo.t
  | Note_item of Note.t

(** [typeid item] returns the TypeId of the underlying entity. *)
val typeid : t -> Uuid.Typeid.t

(** [niceid item] returns the niceid of the underlying entity. *)
val niceid : t -> Identifier.t

(** [entity_type item] returns ["todo"] or ["note"]. *)
val entity_type : t -> string

(** [title item] returns the title of the underlying entity. *)
val title : t -> Title.t

(** [created_at item] returns the creation timestamp. *)
val created_at : t -> Timestamp.t

(** [updated_at item] returns the last-updated timestamp. *)
val updated_at : t -> Timestamp.t
