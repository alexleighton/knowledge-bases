(** Cross-entity query operations.

    Listing, filtering, and sorting across entity types. *)

(** Abstract service handle. *)
type t

(** Errors that can arise from query operations. *)
type error =
  | Repository_error of string
  | Validation_error of string

(** Unified item type returned by listing operations. *)
type item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

(** [init root] initializes the query service from a shared
    {!Repository.Root.t} handle. *)
val init : Repository.Root.t -> t

(** [list t ~entity_type ~statuses] returns todos and/or notes filtered by
    type and status.

    When [entity_type] is [None], both entity types are considered. When it is
    [Some "todo"] or [Some "note"], only that type is listed. [statuses] is a
    set of status strings; when empty, default exclusions apply (exclude done
    todos and archived notes). *)
val list :
  t -> entity_type:string option -> statuses:string list ->
  (item list, error) result
