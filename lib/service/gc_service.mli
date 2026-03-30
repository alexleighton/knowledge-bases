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

(** [init root ~config_svc] initializes the GC service.
    Uses [config_svc] for reading and writing gc_max_age. *)
val init : Repository.Root.t -> config_svc:Config_service.t -> t

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
