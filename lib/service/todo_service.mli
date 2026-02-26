(** Todo-specific service operations.

    Manages todo creation and persistence. *)

(** Abstract service handle. *)
type t

(** Errors that can arise from todo operations. *)
type error =
  | Repository_error of string

(** [init root] initializes the todo service from a shared
    {!Repository.Root.t} handle. *)
val init : Repository.Root.t -> t

(** [add t ~title ~content ?status ()] creates and persists a new todo.
    [status] defaults to [Data.Todo.Open].
    @return the created todo on success. *)
val add :
  t -> title:Data.Title.t -> content:Data.Content.t ->
  ?status:Data.Todo.status -> unit ->
  (Data.Todo.t, error) result
