(** Knowledge base service.

  Orchestrates business operations across repositories and domain data.
*)

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

(** Action taken on AGENTS.md during initialization. *)
type agents_md_action = Created | Appended | Already_present

(** Action taken on .git/info/exclude during initialization. *)
type git_exclude_action = Excluded | Already_excluded

(** Result of a file deletion attempt. *)
type file_action = Deleted | Not_found

(** Result of knowledge-base initialization. *)
type init_result = {
  directory   : string;
  namespace   : string;
  db_file     : string;
  agents_md   : agents_md_action;
  git_exclude : git_exclude_action;
}

(** Result of removing the AGENTS.md section during uninstall. *)
type agents_md_uninstall_action =
  | File_deleted | Section_removed | Section_modified | Not_found

(** Result of removing the .git/info/exclude entry. *)
type git_exclude_uninstall_action = Entry_removed | Entry_not_found

(** Result of knowledge-base uninstallation. *)
type uninstall_result = {
  directory   : string;
  database    : file_action;
  jsonl       : file_action;
  agents_md   : agents_md_uninstall_action;
  git_exclude : git_exclude_uninstall_action;
}

(** A resolved relation entry for display.
    Re-exports {!Show_service.relation_entry}. *)
type relation_entry = Show_service.relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  blocking    : bool option;
}

(** Result of showing a single item, including its relations.
    Re-exports {!Show_service.show_result}. *)
type show_result = Show_service.show_result = {
  item     : item;
  outgoing : relation_entry list;
  incoming : relation_entry list;
}

(** Specification for a single relation in a bulk operation. *)
type relate_spec = Relation_service.relate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
  blocking      : bool;
}

(** Result of a successful relate operation. *)
type relate_result = Relation_service.relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  target_type   : string;
  target_title  : Data.Title.t;
}

(** Errors specific to claim and next operations. *)
type claim_error = Mutation_service.claim_error =
  | Not_a_todo of string
  | Not_open of { niceid : string; status : string }
  | Blocked of { niceid : string; blocked_by : string list }
  | Nothing_available of { stuck_count : int }
  | Service_error of Item_service.error

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

(** [build_specs ~depends_on ~related_to ~uni ~bi ~blocking] constructs a
    {!relate_spec} list from the four relation categories. See
    {!Relation_service.build_specs}. *)
val build_specs :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  blocking:bool ->
  relate_spec list

(** [open_kb ()] finds the git root from the current directory, opens the
    knowledge base at [.kbases.db], and returns the root and service handle.
    Callers must close the root when done. *)
val open_kb : unit -> (Repository.Root.t * t, error) result

(** [init_kb ~directory ~namespace ~gc_max_age] initializes a knowledge base in
    a git repository, creates [.kbases.db], and persists the effective namespace.
    When [gc_max_age] is provided, stores it in the config table. *)
val init_kb :
  directory:string option ->
  namespace:string option ->
  gc_max_age:string option ->
  (init_result, error) result

(** [uninstall_kb ~directory] removes all knowledge-base artifacts from the
    given git repository. Best-effort: individual missing artifacts are reported
    in the result rather than causing failure. *)
val uninstall_kb :
  directory:string option ->
  (uninstall_result, error) result

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

(** Sort order for list results. *)
type sort_order = Query_service.sort_order = Sort_created | Sort_updated

(** Specification for a relation-based filter. *)
type relation_filter = Query_service.relation_filter = {
  target    : string;
  kind      : string;
  direction : Graph_service.direction;
}

(** Specification for a list query. *)
type list_spec = Query_service.list_spec = {
  entity_type      : string option;
  statuses         : string list;
  available        : bool;
  sort             : sort_order option;
  ascending        : bool;
  count_only       : bool;
  relation_filters : relation_filter list;
  transitive       : bool;
  blocked          : bool;
}

(** Result of a list query. *)
type list_result = Query_service.list_result

(** [build_filters ~depends_on ~related_to ~uni ~bi] constructs a
    {!relation_filter} list from the four CLI relation categories.
    See {!Query_service.build_filters}. *)
val build_filters :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  relation_filter list

(** [list t spec] returns items or counts based on the given spec. *)
val list : t -> list_spec -> (list_result, error) result

(** [show t ~identifier] looks up a single item by niceid or TypeId, including
    its outgoing and incoming relations.

    [identifier] is parsed first as a niceid (e.g. ["kb-0"]); if that fails,
    as a TypeId (e.g. ["todo_01jmq..."]). Returns a [Validation_error] if the
    item is not found or the identifier format is unrecognised. *)
val show : t -> identifier:string -> (show_result, error) result

(** [show_many t ~identifiers] looks up multiple items by niceid or TypeId,
    including their relations. Fails on the first unresolvable identifier.
    Returns results in input order. *)
val show_many : t -> identifiers:string list -> (show_result list, error) result

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

(** [reopen t ~identifier] returns a terminal item to its initial status:
    Done todos become Open, Archived notes become Active. *)
val reopen : t -> identifier:string -> (item, error) result

(** Result of a successful deletion. *)
type delete_result = Delete_service.delete_result = {
  niceid            : Data.Identifier.t;
  entity_type       : string;
  relations_removed : int;
}

(** Errors specific to delete operations. *)
type delete_error = Delete_service.delete_error =
  | Blocked_dependency of { niceid : string; dependents : string list }
  | Service_error of Item_service.error

(** [delete t ~identifier ~force] removes an item and its relations.
    When [force] is [false], refuses to delete items that are blocking
    targets of non-terminal items. *)
val delete :
  t -> identifier:string -> force:bool -> (delete_result, delete_error) result

(** [delete_many t ~identifiers ~force] removes multiple items atomically.
    Validates all items before deleting any. *)
val delete_many :
  t ->
  identifiers:string list ->
  force:bool ->
  (delete_result list, delete_error) result

(** [next t] selects the first open, unblocked todo and transitions it to
    [In_Progress]. Returns [Ok None] when no open todos exist. *)
val next : t -> (Data.Todo.t option, claim_error) result

(** [claim t ~identifier] transitions an open, unblocked todo to [In_Progress]. *)
val claim : t -> identifier:string -> (Data.Todo.t, claim_error) result

(** Specification for a single relation to remove. *)
type unrelate_spec = Relation_service.unrelate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
}

(** [build_unrelate_specs ~depends_on ~related_to ~uni ~bi] constructs an
    {!unrelate_spec} list from the four relation categories. *)
val build_unrelate_specs :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  unrelate_spec list

(** Result of a successful unrelate operation. *)
type unrelate_result = Relation_service.unrelate_result = {
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  kind          : Data.Relation_kind.t;
  bidirectional : bool;
}

(** [unrelate t ~source ~specs] removes relations matching the given specs. *)
val unrelate :
  t ->
  source:string ->
  specs:unrelate_spec list ->
  (unrelate_result list, error) result

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

(* --- GC --- *)

(** A single item eligible for garbage collection. *)
type gc_item = Gc_service.gc_item = {
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  age_days    : int;
}

(** Result of a GC run. *)
type gc_result = Gc_service.gc_result = {
  items_removed     : int;
  relations_removed : int;
}

(** Result of reading the configured max age. *)
type max_age_result = Gc_service.max_age_result =
  | Configured of string
  | Default

(** Default max age as a display string. *)
val default_max_age_display : string

(** [gc_get_max_age t] reads the gc_max_age from config. *)
val gc_get_max_age : t -> (max_age_result, error) result

(** [gc_set_max_age t age_str] validates and persists a new gc_max_age. *)
val gc_set_max_age : t -> string -> (unit, error) result

(** [gc_collect_with_config t] identifies eligible items without removing them. *)
val gc_collect_with_config : t -> (gc_item list, error) result

(** [gc_run_with_config t] removes eligible items and their relations. *)
val gc_run_with_config : t -> (gc_result, error) result

(* --- Sync --- *)

(** [flush t] forces a flush of all SQLite data to the JSONL file.
    Returns an error if sync is not enabled. *)
val flush : t -> (unit, error) result

(** [force_rebuild t] unconditionally replaces all SQLite data with the
    contents of the JSONL file. Returns an error if sync is not enabled. *)
val force_rebuild : t -> (unit, error) result
