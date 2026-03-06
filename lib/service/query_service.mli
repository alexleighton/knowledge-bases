(** Cross-entity query operations.

    Listing, filtering, and sorting across entity types. *)

(** Abstract service handle. *)
type t

(** Errors that can arise from query operations. *)
type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

(** Unified item type returned by listing operations. *)
type item = Item_service.item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

(** A resolved relation entry for display. *)
type relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  blocking    : bool option;
}

(** Result of showing a single item, including its relations. *)
type show_result = {
  item     : item;
  outgoing : relation_entry list;
  incoming : relation_entry list;
}

(** [init root] initializes the query service from a shared
    {!Repository.Root.t} handle. *)
val init : Repository.Root.t -> t

(** [list t ~entity_type ~statuses ?available ()] returns todos and/or notes
    filtered by type and status.

    When [entity_type] is [None], both entity types are considered. When it is
    [Some "todo"] or [Some "note"], only that type is listed. [statuses] is a
    set of status strings; when empty, default exclusions apply (exclude done
    todos and archived notes).

    When [available] is [true], returns only open unblocked todos, ignoring
    [entity_type] and [statuses]. *)
val list :
  t -> entity_type:string option -> statuses:string list ->
  ?available:bool -> unit ->
  (item list, error) result

(** [show t ~identifier] looks up a single item by niceid or TypeId, including
    its outgoing and incoming relations.

    [identifier] is parsed first as a niceid (e.g. ["kb-0"]); if that fails,
    as a TypeId (e.g. ["todo_01jmq..."]). Returns a [Validation_error] if the
    item is not found or the identifier format is unrecognised. *)
val show : t -> identifier:string -> (show_result, error) result

(** [show_many t ~identifiers] looks up multiple items by niceid or TypeId,
    including their relations. Resolves all identifiers in order, failing on
    the first error. Returns results in input order. *)
val show_many : t -> identifiers:string list -> (show_result list, error) result
