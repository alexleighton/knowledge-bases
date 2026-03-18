(** Entity deletion with cascade and blocking guard.

    Assumes it is called within a transaction — the transaction boundary
    is owned by {!Kb_service}. *)

(** Abstract service handle. *)
type t

(** Result of a successful deletion. *)
type delete_result = {
  niceid           : Data.Identifier.t;
  entity_type      : string;
  relations_removed : int;
}

(** Errors specific to delete operations. *)
type delete_error =
  | Blocked_dependency of { niceid : string; dependents : string list }
  | Service_error of Item_service.error

(** [cascade_delete ~todo_repo ~note_repo ~relation_repo ~niceid_repo
    ~map_err ~typeid ~niceid ~entity_type] deletes an entity and all its
    ancillary data (relations, niceid mapping).  [map_err] translates
    repository errors into the caller's error type.

    Returns the number of relations removed. *)
val cascade_delete :
  todo_repo:Repository.Todo.t ->
  note_repo:Repository.Note.t ->
  relation_repo:Repository.Relation.t ->
  niceid_repo:Repository.Niceid.t ->
  map_err:([> `Todo of Repository.Todo.error
           | `Note of Repository.Note.error
           | `Rel of Repository.Relation.error
           | `Niceid of Repository.Niceid.error ] -> 'e) ->
  typeid:Data.Uuid.Typeid.t ->
  niceid:Data.Identifier.t ->
  entity_type:string ->
  (int, 'e) result

(** [init root] initializes the delete service. *)
val init : Repository.Root.t -> t

(** [delete t ~identifier ~force] removes the item identified by [identifier]
    and all of its relations.

    When [force] is [false], checks that no non-terminal item has a blocking
    relation targeting the item being deleted. Returns [Blocked_dependency]
    if such items exist.

    When [force] is [true], skips the blocking check. *)
val delete :
  t -> identifier:string -> force:bool -> (delete_result, delete_error) result

(** [delete_many t ~identifiers ~force] validates all items first, then
    deletes them. If any item fails the blocking check, the entire batch
    fails before any deletion. *)
val delete_many :
  t ->
  identifiers:string list ->
  force:bool ->
  (delete_result list, delete_error) result
