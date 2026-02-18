(** Knowledge base service.

  Orchestrates business operations across repositories and domain data.
*)

(** Abstract service handle. *)
type t

(** Errors that can arise from service operations. *)
type error =
  | Repository_error of string
  | Validation_error of string

(** Result of knowledge-base initialization. *)
type init_result = {
  directory : string;
  namespace : string;
  db_file   : string;
}

(** [init root] initializes the service from a shared {!Repository.Root.t}
    handle. The service does not own the root — callers manage its lifecycle. *)
val init : Repository.Root.t -> t

(** [init_kb ~directory ~namespace] initializes a knowledge base in a git
    repository, creates [.kbases.db], and persists the effective namespace. *)
val init_kb :
  directory:string option ->
  namespace:string option ->
  (init_result, error) result

(** [add_note t ~title ~content] creates and persists a new note.
    @return the created note on success. *)
val add_note : t -> title:Data.Title.t -> content:Data.Content.t -> (Data.Note.t, error) result
