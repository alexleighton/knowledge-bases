(** Todo repository API. *)

(** Abstract handle to the repository backend. *)
type t

(** Errors that can arise while interacting with stored todos. *)
type error =
  | Not_found of [ `Id of Data.Todo.id | `Niceid of Data.Identifier.t ]
  | Duplicate_niceid of Data.Identifier.t
  | Backend_failure of string

(** [init ~db ~niceid_repo] ensures required tables exist in [db] and returns a
    handle that will use [niceid_repo] to generate nice ids. *)
val init :
  db:Sqlite3.db ->
  niceid_repo:Niceid.t ->
  (t, error) result

(** [create repo ~title ~content ?status ()] stores a new todo, generating
    identifiers for it. [status] defaults to [Data.Todo.Open].

    @return the newly stored todo on success.
    @return [Error Duplicate_niceid _] if the generated nice id already exists.
    @return [Error Backend_failure _] if the underlying storage fails. *)
val create :
  t ->
  title:Data.Title.t ->
  content:Data.Content.t ->
  ?status:Data.Todo.status ->
  unit ->
  (Data.Todo.t, error) result

(** [get repo id] fetches the todo identified by TypeId [id]. *)
val get : t -> Data.Todo.id -> (Data.Todo.t, error) result

(** [get_by_niceid repo niceid] fetches the todo identified by [niceid]. *)
val get_by_niceid : t -> Data.Identifier.t -> (Data.Todo.t, error) result

(** [update repo todo] overwrites the persisted representation of [todo]. *)
val update : t -> Data.Todo.t -> (Data.Todo.t, error) result

(** [delete repo niceid] removes the todo identified by [niceid]. *)
val delete : t -> Data.Identifier.t -> (unit, error) result

(** [list repo ~statuses] returns todos filtered by [statuses].

    When [statuses] is empty, all todos except those with status [Done] are returned. *)
val list :
  t ->
  statuses:Data.Todo.status list ->
  (Data.Todo.t list, error) result

(** [list_all repo] returns every todo regardless of status, ordered by id. *)
val list_all : t -> (Data.Todo.t list, error) result

(** [delete_all repo] removes every todo from the table. *)
val delete_all : t -> (unit, error) result

(** [import repo ~id ~title ~content ?status ()] inserts a todo with a
    caller-provided TypeId, allocating a fresh niceid. Used during rebuild
    from JSONL. [status] defaults to [Data.Todo.Open]. *)
val import :
  t ->
  id:Data.Todo.id ->
  title:Data.Title.t ->
  content:Data.Content.t ->
  ?status:Data.Todo.status ->
  unit ->
  (Data.Todo.t, error) result
