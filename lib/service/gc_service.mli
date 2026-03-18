(** Garbage collection for terminal items past their age threshold.

    Collects connected components where every item is terminal and
    older than [max_age_seconds]. *)

(** Abstract service handle. *)
type t

(** A single item eligible for collection. *)
type gc_item = {
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  age_days    : int;
}

(** Result of a GC run. *)
type gc_result = {
  items_removed     : int;
  relations_removed : int;
}

(** Default max age as a display string. *)
val default_max_age_display : string

(** [init root] initializes the GC service. *)
val init : Repository.Root.t -> t

(** Result of reading the configured max age. *)
type max_age_result =
  | Configured of string
  | Default

(** [get_max_age t] reads the gc_max_age from config. *)
val get_max_age : t -> (max_age_result, Item_service.error) result

(** [set_max_age t age_str] validates and persists a new gc_max_age. *)
val set_max_age : t -> string -> (unit, Item_service.error) result

(** [collect t ~max_age_seconds ~now] identifies eligible items without
    removing them (dry-run). Returns items grouped by connected component
    where every member is terminal and age-eligible. *)
val collect :
  t -> max_age_seconds:int -> now:int -> (gc_item list, Item_service.error) result

(** [run t ~max_age_seconds ~now] removes eligible items and their relations.
    Returns counts of removed items and relations. *)
val run :
  t -> max_age_seconds:int -> now:int -> (gc_result, Item_service.error) result

(** [collect_with_config t] like [collect] but reads max age from config. *)
val collect_with_config :
  t -> (gc_item list, Item_service.error) result

(** [run_with_config t] like [run] but reads max age from config. *)
val run_with_config :
  t -> (gc_result, Item_service.error) result
