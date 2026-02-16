(** Knowledge base service.

  Orchestrates business operations across repositories and domain data.
*)

(** Abstract service handle. *)
type t

(** Errors that can arise from service operations. *)
type error =
  | Repository_error of string
  | Validation_error of string

(** [init root] initializes the service from a shared {!Repository.Root.t}
    handle. The service does not own the root — callers manage its lifecycle. *)
val init : Repository.Root.t -> t

(** [add_note t ~title ~content] creates and persists a new note.
    @return the created note on success. *)
val add_note : t -> title:string -> content:string -> (Data.Note.t, error) result
