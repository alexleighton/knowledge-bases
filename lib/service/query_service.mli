(** Cross-entity query operations.

    Listing, filtering, sorting, and counting across entity types. *)

(** Abstract service handle. *)
type t

(** Errors that can arise from query operations. *)
type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

(** Unified item type returned by listing operations. *)
type item = Data.Item.t =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

(** Sort order for list results. *)
type sort_order = Sort_created | Sort_updated

(** Specification for a relation-based filter. *)
type relation_filter = {
  target    : string;
  kind      : string;
  direction : Graph_service.direction;
}

(** Specification for a list query. *)
type list_spec = {
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
type list_result =
  | Items of item list
  | Counts of { todos : (string * int) list; notes : (string * int) list }

(** [build_filters ~depends_on ~related_to ~uni ~bi] constructs a
    {!relation_filter} list from the four CLI relation categories. *)
val build_filters :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  relation_filter list

(** Default list_spec with sensible defaults. *)
val default_list_spec : list_spec

(** [init root] initializes the query service from a shared
    {!Repository.Root.t} handle. *)
val init : Repository.Root.t -> t

(** [list t spec] returns items or counts based on the given spec.

    Flag interaction validation:
    - [available] and [statuses] cannot both be set.
    - [sort] and [count_only] cannot both be set.
    - [transitive] requires exactly one relation filter. *)
val list : t -> list_spec -> (list_result, error) result
