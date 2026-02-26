(** Note-specific service operations.

    Manages note creation and persistence. *)

(** Abstract service handle. *)
type t

(** Errors that can arise from note operations. *)
type error =
  | Repository_error of string

(** [init root] initializes the note service from a shared
    {!Repository.Root.t} handle. *)
val init : Repository.Root.t -> t

(** [add t ~title ~content] creates and persists a new note.
    @return the created note on success. *)
val add :
  t -> title:Data.Title.t -> content:Data.Content.t ->
  (Data.Note.t, error) result
