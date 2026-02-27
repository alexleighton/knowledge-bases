module Sql = Sqlite3

type t

(** Errors that can arise during root initialization. *)
type error = Backend_failure of string

(** [init ~db_file ~namespace] opens or creates a single SQLite connection,
    initializes all repositories against it, and returns shared handles.
    [namespace] is used if provided; otherwise the value is looked up from the
    config repository.

    @return [Error (Backend_failure msg)] if the database cannot be opened or
    a repository fails to initialize. *)
val init :
  db_file:string ->
  namespace:string option ->
  (t, error) result

(** Accessors for shared repositories and the underlying db connection. *)
val niceid : t -> Niceid.t
val note : t -> Note.t
val todo : t -> Todo.t
val relation : t -> Relation.t
val config : t -> Config.t
val db : t -> Sql.db

(** Close the shared database connection. *)
val close : t -> unit
