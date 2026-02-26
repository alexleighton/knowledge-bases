(** Shared cross-entity service types and identifier resolution.

    This module owns the shared [error] and [item] types used by all
    cross-entity services, plus the identifier-resolution logic that
    maps a niceid or TypeId string to an item. *)

(** Shared service-level error type. *)
type error = Repository_error of string | Validation_error of string

(** Shared item type for cross-entity results. *)
type item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

(** Abstract service handle. *)
type t

(** [init root] initializes the item service from a shared
    {!Repository.Root.t} handle. *)
val init : Repository.Root.t -> t

(** [find t ~identifier] resolves a niceid or TypeId string to an item.

    [identifier] is parsed first as a niceid (e.g. ["kb-0"]); if that fails,
    as a TypeId (e.g. ["todo_01abc..."]). Returns a [Validation_error] if the
    item is not found or the identifier format is unrecognised. *)
val find : t -> identifier:string -> (item, error) result

(** [map_repo_error ~entity_name err] maps a repository error to a service error.
    [entity_name] (e.g. ["todo"], ["note"]) is used in the not-found message. *)
val map_repo_error : entity_name:string -> Repository.Entity_repo.error -> error
