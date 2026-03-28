(** Knowledge base service.

  Orchestrates business operations across repositories and domain data.
*)

(** Sub-service module aliases for type access. *)

module Lifecycle = Lifecycle
module Query = Query_service
module Show = Show_service
module Mutation = Mutation_service
module Relation = Relation_service
module Delete = Delete_service
module Gc = Gc_service

(** Abstract service handle. *)
type t

(** Errors that can arise from service operations. *)
type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

(** Unified item type returned by listing operations.
    Re-exports {!Data.Item.t}. *)
type item = Data.Item.t =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

(** Result of an [add_*_with_relations] operation. *)
type add_with_relations_result = {
  niceid      : Data.Identifier.t;
  typeid      : Data.Uuid.Typeid.t;
  entity_type : string;
  relations   : Show.relation_entry list;
}

(* --- Lifecycle --- *)

(** [init root] initializes the service from a shared {!Repository.Root.t}
    handle. The service does not own the root — callers manage its lifecycle. *)
val init : Repository.Root.t -> t

(** [open_kb ()] finds the git root from the current directory, opens the
    knowledge base at [.kbases.db], and returns the root and service handle.
    Callers must close the root when done. *)
val open_kb : unit -> (Repository.Root.t * t, error) result

(** [init_kb ~directory ~namespace ~gc_max_age ~mode] initializes a knowledge
    base in a git repository, creates [.kbases.db], and persists the effective
    namespace.  When [gc_max_age] is provided, stores it in the config table.
    [mode] selects ["local"] or ["shared"]; defaults to ["shared"]. *)
val init_kb :
  directory:string option ->
  namespace:string option ->
  gc_max_age:string option ->
  mode:string option ->
  (Lifecycle.init_result, error) result

(** [uninstall_kb ~directory] removes all knowledge-base artifacts from the
    given git repository. Best-effort: individual missing artifacts are reported
    in the result rather than causing failure. *)
val uninstall_kb :
  directory:string option ->
  (Lifecycle.uninstall_result, error) result

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
  specs:Relation.relate_spec list ->
  (add_with_relations_result, error) result

(** [add_todo_with_relations t ~title ~content ~specs ?status ()] creates a
    todo and all specified relations atomically. Fails with no side effects if
    any spec is invalid. *)
val add_todo_with_relations :
  t ->
  title:Data.Title.t ->
  content:Data.Content.t ->
  specs:Relation.relate_spec list ->
  ?status:Data.Todo.status ->
  unit ->
  (add_with_relations_result, error) result

(* --- Query --- *)

(** [build_filters ~depends_on ~related_to ~uni ~bi] constructs a
    {!Query.relation_filter} list from the four CLI relation categories.
    See {!Query_service.build_filters}. *)
val build_filters :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  Query.relation_filter list

(** [list t spec] returns items or counts based on the given spec. *)
val list : t -> Query.list_spec -> (Query.list_result, error) result

(** [show t ~identifier] looks up a single item by niceid or TypeId, including
    its outgoing and incoming relations. *)
val show : t -> identifier:string -> (Show.show_result, error) result

(** [show_many t ~identifiers] looks up multiple items by niceid or TypeId,
    including their relations. Fails on the first unresolvable identifier.
    Returns results in input order. *)
val show_many : t -> identifiers:string list -> (Show.show_result list, error) result

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

(** [resolve_many t ~identifiers] resolves multiple todos atomically. *)
val resolve_many : t -> identifiers:string list -> (Data.Todo.t list, error) result

(** [archive_many t ~identifiers] archives multiple notes atomically. *)
val archive_many : t -> identifiers:string list -> (Data.Note.t list, error) result

(** [reopen_many t ~identifiers] reopens multiple terminal items atomically. *)
val reopen_many : t -> identifiers:string list -> (item list, error) result

(** [next t] selects the first open, unblocked todo and transitions it to
    [In_Progress]. Returns [Ok None] when no open todos exist. *)
val next : t -> (Data.Todo.t option, Mutation.claim_error) result

(** [claim t ~identifier] transitions an open, unblocked todo to [In_Progress]. *)
val claim : t -> identifier:string -> (Data.Todo.t, Mutation.claim_error) result

(* --- Relations --- *)

(** [build_specs ~depends_on ~related_to ~uni ~bi ~blocking] constructs a
    {!Relation.relate_spec} list from the four relation categories. *)
val build_specs :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  blocking:bool ->
  Relation.relate_spec list

(** [relate t ~source ~specs] creates one or more relations from [source]
    atomically. All specs are validated before any relation is inserted. *)
val relate :
  t ->
  source:string ->
  specs:Relation.relate_spec list ->
  (Relation.relate_result list, error) result

(** [build_unrelate_specs ~depends_on ~related_to ~uni ~bi] constructs an
    {!Relation.unrelate_spec} list from the four relation categories. *)
val build_unrelate_specs :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  Relation.unrelate_spec list

(** [unrelate t ~source ~specs] removes relations matching the given specs. *)
val unrelate :
  t ->
  source:string ->
  specs:Relation.unrelate_spec list ->
  (Relation.unrelate_result list, error) result

(* --- Delete --- *)

(** [delete_many t ~identifiers ~force] removes one or more items atomically.
    Validates all items before deleting any. *)
val delete_many :
  t ->
  identifiers:string list ->
  force:bool ->
  (Delete.delete_result list, Delete.delete_error) result

(* --- GC --- *)

(** [gc_get_max_age t] reads the gc_max_age from config. *)
val gc_get_max_age : t -> (Gc.max_age_result, error) result

(** [gc_set_max_age t age_str] validates and persists a new gc_max_age. *)
val gc_set_max_age : t -> string -> (unit, error) result

(** [gc_collect_with_config t] identifies eligible items without removing them. *)
val gc_collect_with_config : t -> (Gc.gc_item list, error) result

(** [gc_run_with_config t] removes eligible items and their relations. *)
val gc_run_with_config : t -> (Gc.gc_result, error) result

(* --- Sync --- *)

(** [flush t] forces a flush of all SQLite data to the JSONL file.
    Returns an error in local mode (sync is not available). *)
val flush : t -> (unit, error) result

(** [force_rebuild t] unconditionally replaces all SQLite data with the
    contents of the JSONL file.
    Returns an error in local mode (sync is not available). *)
val force_rebuild : t -> (unit, error) result
