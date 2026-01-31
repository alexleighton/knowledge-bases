module Sql = Sqlite3

type t

(** [init ~db_file ~namespace] opens or creates a single SQLite connection,
    initializes all repositories against it, and returns shared handles.
    Raises [Failure] if initialization fails. *)
val init : db_file:string -> namespace:string -> t

(** Accessors for shared repositories and the underlying db connection. *)
val niceid : t -> Niceid.t
val note : t -> Note.t
val db : t -> Sql.db

(** Close the shared database connection. *)
val close : t -> unit

