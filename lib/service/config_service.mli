(** Configuration service for inspecting and modifying knowledge-base settings.

    Provides a registry of user-facing config keys with validation, defaults,
    and side effects. Bypasses {!Kb_service} and operates directly on
    {!Repository.Root.t} to avoid GC/rebuild overhead. *)

(** A single config key-value pair.
    [is_default] is [true] when the value comes from the registry default
    rather than an explicit database entry. *)
type config_value = { key : string; value : string; is_default : bool }

(** Errors that can arise from config operations. *)
type error =
  | Unknown_key of string
  | Validation_error of string
  | Nothing_to_update
  | Backend_error of string

(** Default gc_max_age value as a string of seconds. *)
val default_gc_max_age : string

(** Abstract service handle. *)
type t

(** [init root ~dir] creates a config service from a root handle and
    the knowledge-base directory path. *)
val init : Repository.Root.t -> dir:string -> t

(** [get t key] retrieves a user-facing config value by key. Falls back to
    the registry default when the key has not been explicitly set.
    Returns [Unknown_key] for internal or nonexistent keys. *)
val get : t -> string -> (config_value, error) result

(** [set ?run_on_set t key value] validates and persists a new config value.
    When [run_on_set] is [true] (the default), runs side effects required by
    the key after writing (e.g. namespace rename, JSONL flush on mode change).

    Pass [~run_on_set:false] only during knowledge-base initialization, where
    the database is empty and side effects (renaming niceids, flushing JSONL)
    have nothing to act on. All other callers must use the default.

    Returns [Nothing_to_update] when the new value matches the current value
    or the default. *)
val set : ?run_on_set:bool -> t -> string -> string -> (unit, error) result

(** [list_user_facing t] returns all user-facing config keys with their
    current or default values. *)
val list_user_facing : t -> (config_value list, error) result
