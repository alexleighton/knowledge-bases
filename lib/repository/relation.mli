(** Relation repository API. *)

(** Abstract handle to the repository backend. *)
type t

(** Errors that can arise while interacting with stored relations. *)
type error =
  | Duplicate
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

(** [delete_all repo] removes every relation from the table. *)
val delete_all : t -> (unit, error) result
