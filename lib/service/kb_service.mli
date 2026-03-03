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

(** Action taken on AGENTS.md during initialization. *)
type agents_md_action = Created | Appended | Already_present

(** Action taken on .git/info/exclude during initialization. *)
type git_exclude_action = Excluded | Already_excluded

(** Result of knowledge-base initialization. *)
type init_result = {
  directory   : string;
  namespace   : string;
  db_file     : string;
  agents_md   : agents_md_action;
  git_exclude : git_exclude_action;
}

(** A resolved relation entry for display. *)
type relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
}

(** Result of showing a single item, including its relations. *)
type show_result = {
  item     : item;
  outgoing : relation_entry list;
  incoming : relation_entry list;
}

(** Specification for a single relation in a bulk operation. *)
type relate_spec = Relation_service.relate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
}

(** Result of a successful relate operation. *)
type relate_result = Relation_service.relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  target_type   : string;
  target_title  : Data.Title.t;
}

(** Result of an [add_*_with_relations] operation. *)
type add_with_relations_result = {
  niceid      : Data.Identifier.t;
  typeid      : Data.Uuid.Typeid.t;
  entity_type : string;
  relations   : relation_entry list;
}

(* --- Lifecycle --- *)

(** [init root] initializes the service from a shared {!Repository.Root.t}
    handle. The service does not own the root — callers manage its lifecycle. *)
val init : Repository.Root.t -> t

(** [build_specs ~depends_on ~related_to ~uni ~bi] constructs a
    {!relate_spec} list from the four relation categories. See
    {!Relation_service.build_specs}. *)
val build_specs :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  relate_spec list

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

(* --- Create --- *)

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

(** [add_note_with_relations t ~title ~content ~specs] creates a note and all
    specified relations atomically. Fails with no side effects if any spec is
    invalid. *)
val add_note_with_relations :
  t ->
  title:Data.Title.t ->
  content:Data.Content.t ->
  specs:relate_spec list ->
  (add_with_relations_result, error) result

(** [add_todo_with_relations t ~title ~content ~specs ?status ()] creates a
    todo and all specified relations atomically. Fails with no side effects if
    any spec is invalid. *)
val add_todo_with_relations :
  t ->
  title:Data.Title.t ->
  content:Data.Content.t ->
  specs:relate_spec list ->
  ?status:Data.Todo.status ->
  unit ->
  (add_with_relations_result, error) result

(* --- Query --- *)

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

(** [show t ~identifier] looks up a single item by niceid or TypeId, including
    its outgoing and incoming relations.

    [identifier] is parsed first as a niceid (e.g. ["kb-0"]); if that fails,
    as a TypeId (e.g. ["todo_01jmq..."]). Returns a [Validation_error] if the
    item is not found or the identifier format is unrecognised. *)
val show : t -> identifier:string -> (show_result, error) result

(* --- Modify --- *)

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

(** [relate t ~source ~specs] creates one or more relations from [source]
    atomically. All specs are validated before any relation is inserted.

    @return [Ok relate_result list] on success.
    @return [Validation_error] if any item is not found, any kind is
            invalid, or any relation already exists. *)
val relate :
  t ->
  source:string ->
  specs:relate_spec list ->
  (relate_result list, error) result

(* --- Sync --- *)

(** [flush t] forces a flush of all SQLite data to the JSONL file.
    Returns an error if sync is not enabled. *)
val flush : t -> (unit, error) result

(** [force_rebuild t] unconditionally replaces all SQLite data with the
    contents of the JSONL file. Returns an error if sync is not enabled. *)
val force_rebuild : t -> (unit, error) result
