(** Niceid allocator repository backed by SQLite. *)

(** Abstract handle to the niceid allocator. *)
type t

(** Errors that can arise while interacting with the allocator. *)
type error =
  | Backend_failure of string

(** [init ~db ~namespace] ensures the [niceid] table exists in [db] and returns
    a handle that will mint identifiers under [namespace]. *)
val init : db:Sqlite3.db -> namespace:string -> (t, error) result

(** [allocate repo typeid] starts a transaction, finds the current maximum
    allocated niceid, increments it (starting from 0), associates it with
    [typeid], and returns the resulting {!Data.Identifier.t}. *)
val allocate :
  t ->
  Data.Uuid.Typeid.t ->
  (Data.Identifier.t, error) result
