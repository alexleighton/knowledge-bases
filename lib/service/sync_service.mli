(** Sync service — orchestrates flush and rebuild between SQLite and JSONL. *)

(** Abstract service handle. *)
type t

(** Errors from sync operations. *)
type error = Sync_failed of string

(** [init root ~jsonl_path] creates a sync service that will read/write
    the JSONL file at [jsonl_path] and use [root] for repository access. *)
val init : Repository.Root.t -> jsonl_path:string -> t

(** [mark_dirty t] sets the dirty flag in the config table, indicating
    unflushed writes exist. Called before each write operation. *)
val mark_dirty : t -> (unit, error) result

(** [flush t] queries all entities from SQLite and writes them to the
    JSONL file. Skips if the dirty flag is not set. Clears the dirty
    flag and stores the content hash on success. *)
val flush : t -> (unit, error) result

(** [rebuild_if_needed t] checks whether the JSONL file has changed
    externally (hash mismatch) or if unflushed writes exist (dirty flag),
    and takes the appropriate action. *)
val rebuild_if_needed : t -> (unit, error) result

(** [force_rebuild t] unconditionally replaces all SQLite data with the
    contents of the JSONL file. *)
val force_rebuild : t -> (unit, error) result
