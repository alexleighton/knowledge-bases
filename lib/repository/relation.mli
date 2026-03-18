(** Relation repository API. *)

(** Abstract handle to the repository backend. *)
type t

(** Errors that can arise while interacting with stored relations. *)
type error =
  | Duplicate
  | Not_found
  | Backend_failure of string

(** [init ~db] ensures the relation table exists in [db] and returns a handle. *)
val init : db:Sqlite3.db -> (t, error) result

(** [create repo relation] inserts a new relation.

    For bidirectional relations, checks that the reverse
    [(target, source, kind)] does not already exist.

    @return the relation on success.
    @return [Error Duplicate] if the relation (or its reverse, for
            bidirectional relations) already exists.
    @return [Error (Backend_failure _)] if the underlying storage fails. *)
val create : t -> Data.Relation.t -> (Data.Relation.t, error) result

(** [list_all repo] returns every relation, ordered by source, target, kind. *)
val list_all : t -> (Data.Relation.t list, error) result

(** [find_by_source repo typeid] returns relations where [typeid] is the source. *)
val find_by_source : t -> Data.Uuid.Typeid.t -> (Data.Relation.t list, error) result

(** [find_by_target repo typeid] returns relations where [typeid] is the target. *)
val find_by_target : t -> Data.Uuid.Typeid.t -> (Data.Relation.t list, error) result

(** [delete repo ~source ~target ~kind ~bidirectional] deletes a single
    relation by its composite key.  When [bidirectional] is [true] and the
    [(source, target, kind)] row is not found, the reverse
    [(target, source, kind)] is tried.

    @return [Error Not_found] if no matching row exists. *)
val delete :
  t ->
  source:Data.Uuid.Typeid.t ->
  target:Data.Uuid.Typeid.t ->
  kind:Data.Relation_kind.t ->
  bidirectional:bool ->
  (unit, error) result

(** [delete_by_entity repo typeid] deletes every relation where [typeid]
    appears as source or target.

    @return the number of deleted rows. *)
val delete_by_entity : t -> Data.Uuid.Typeid.t -> (int, error) result

(** [delete_all repo] removes every relation from the table. *)
val delete_all : t -> (unit, error) result
