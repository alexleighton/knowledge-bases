(** Knowledge base service.

  Orchestrates business operations across repositories and domain data.
*)

(** Abstract service handle. *)
type t

(** Errors that can arise from service operations. *)
type error =
  | Repository_error of string
  | Validation_error of string

(** Unified item type returned by listing operations. *)
type item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

(** Result of knowledge-base initialization. *)
type init_result = {
  directory : string;
  namespace : string;
  db_file   : string;
}

(** Result of a successful relate operation. *)
type relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
}

(** [init root] initializes the service from a shared {!Repository.Root.t}
    handle. The service does not own the root — callers manage its lifecycle. *)
val init : Repository.Root.t -> t

(** Database filename used for knowledge bases (e.g. [.kbases.db]). *)
val db_filename : string

(** [open_kb ()] finds the git root from the current directory, opens the
    knowledge base at [.kbases.db], and returns the root and service handle.
    Callers must close the root when done. *)
val open_kb : unit -> (Repository.Root.t * t, error) result

(** [init_kb ~directory ~namespace] initializes a knowledge base in a git
    repository, creates [.kbases.db], and persists the effective namespace. *)
val init_kb :
  directory:string option ->
  namespace:string option ->
  (init_result, error) result

(** [add_note t ~title ~content] creates and persists a new note.
    @return the created note on success. *)
val add_note : t -> title:Data.Title.t -> content:Data.Content.t -> (Data.Note.t, error) result

(** [add_todo t ~title ~content ?status ()] creates and persists a new todo.
    [status] defaults to [Data.Todo.Open].
    @return the created todo on success. *)
val add_todo :
  t ->
  title:Data.Title.t ->
  content:Data.Content.t ->
  ?status:Data.Todo.status ->
  unit ->
  (Data.Todo.t, error) result

(** [list t ~entity_type ~statuses] returns todos and/or notes filtered by type and status.

    When [entity_type] is [None], both entity types are considered. When it is
    [Some "todo"] or [Some "note"], only that type is listed. [statuses] is a
    set of status strings; when empty, default exclusions apply (exclude done
    todos and archived notes). *)
val list :
  t ->
  entity_type:string option ->
  statuses:string list ->
  (item list, error) result

(** [show t ~identifier] looks up a single item by niceid or TypeId.

    [identifier] is parsed first as a niceid (e.g. ["kb-0"]); if that fails,
    as a TypeId (e.g. ["todo_01jmq..."]). Returns a [Validation_error] if the
    item is not found or the identifier format is unrecognised. *)
val show : t -> identifier:string -> (item, error) result

(** [update t ~identifier ?status ?title ?content ()] applies changes to the
    item identified by [identifier].  At least one of [status], [title], or
    [content] must be provided. *)
val update :
  t ->
  identifier:string ->
  ?status:string ->
  ?title:Data.Title.t ->
  ?content:Data.Content.t ->
  unit ->
  (item, error) result

(** [resolve t ~identifier] sets a todo's status to [Done]. *)
val resolve : t -> identifier:string -> (Data.Todo.t, error) result

(** [archive t ~identifier] sets a note's status to [Archived]. *)
val archive : t -> identifier:string -> (Data.Note.t, error) result

(** [relate t ~source ~target ~kind ~bidirectional] creates a relation
    between the items identified by [source] and [target].

    @return [Ok relate_result] on success.
    @return [Validation_error] if either item is not found, the kind is
            invalid, or the relation already exists. *)
val relate :
  t ->
  source:string ->
  target:string ->
  kind:string ->
  bidirectional:bool ->
  (relate_result, error) result
