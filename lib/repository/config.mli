(** Configuration repository API.

    Provides a simple key/value store backed by the shared database,
    exposing helpers to persist settings such as the namespace. *)

module Sql = Sqlite3

(** Abstract handle to the configuration repository. *)
type t

(** Errors that can arise while interacting with configuration values. *)
type error =
  | Not_found of string
      (** Requested key is missing. *)
  | Backend_failure of string
      (** Underlying database operation failed. *)

(** [init ~db] ensures the configuration table exists in [db] and returns
    a handle that operates on it. *)
val init : db:Sql.db -> (t, error) result

(** [get t key] retrieves the value stored for [key].
    @return [Error (Not_found key)] when [key] does not exist. *)
val get : t -> string -> (string, error) result

(** [set t key value] stores or updates [key] with [value]. *)
val set : t -> string -> string -> (unit, error) result

(** [delete t key] removes [key] from storage.
    @return [Error (Not_found key)] when [key] does not exist. *)
val delete : t -> string -> (unit, error) result
