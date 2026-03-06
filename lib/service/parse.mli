(** Composite parsing with [Validation_error] wrapping.

    Each function delegates to a Data-layer result-returning parser
    and wraps the [string] error into {!Item_service.Validation_error}. *)

(** Parsed form of a user-supplied identifier.
    Re-exported from {!Item_service.parsed_identifier}. *)
type parsed_identifier = Item_service.parsed_identifier =
  | Niceid of Data.Identifier.t
  | Typeid of Data.Uuid.Typeid.t

(** [identifier s] interprets [s] as a niceid or typeid. *)
val identifier : string -> (parsed_identifier, Item_service.error) result

(** [todo_status s] parses [s] as a todo status. *)
val todo_status : string -> (Data.Todo.status, Item_service.error) result

(** [note_status s] parses [s] as a note status. *)
val note_status : string -> (Data.Note.status, Item_service.error) result

(** [relation_kind s] parses [s] as a relation kind. *)
val relation_kind : string -> (Data.Relation_kind.t, Item_service.error) result

(** [entity_type s] validates an entity type string. *)
val entity_type : string -> (string, Item_service.error) result
