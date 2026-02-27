(** Note repository API.

    This module defines the CRUD surface that higher layers should use to
    persist {!Note_data.t} values. The implementation will be backed by a database
    in a later iteration. *)

(** Abstract handle to the repository backend. *)
type t

(** Errors that can arise while interacting with stored notes. *)
type error =
  | Not_found of [ `Id of Data.Note.id | `Niceid of Data.Identifier.t ]
  | Duplicate_niceid of Data.Identifier.t
  | Backend_failure of string

(** [init ~db ~niceid_repo] ensures required tables exist in [db] and returns a
    handle that will use [niceid_repo] to generate nice ids. *)
val init :
  db:Sqlite3.db ->
  niceid_repo:Niceid.t ->
  (t, error) result

(** [create repo ~title ~content ?status] stores a new note, generating identifiers
    for it. [status] defaults to [Data.Note.Active].

    @return the newly stored note on success.
    @return [Error Duplicate_niceid _] if the generated nice id already exists.
    @return [Error Backend_failure _] if the underlying storage fails. *)
val create :
  t ->
  title:Data.Title.t ->
  content:Data.Content.t ->
  ?status:Data.Note.status ->
  unit ->
  (Data.Note.t, error) result

(** [get repo id] fetches the note identified by TypeId [id].

    @return [Error Not_found (`Id _)] if the note does not exist.
    @return [Error Backend_failure _] if the underlying storage fails. *)
val get : t -> Data.Note.id -> (Data.Note.t, error) result

(** [get_by_niceid repo niceid] fetches the note identified by [niceid].

    @return [Error Not_found (`Niceid _)] if the note does not exist.
    @return [Error Backend_failure _] if the underlying storage fails. *)
val get_by_niceid : t -> Data.Identifier.t -> (Data.Note.t, error) result

(** [update repo note] overwrites the persisted representation of [note].

    @return the updated note on success.
    @return [Error Not_found _] if the target note does not exist.
    @return [Error Backend_failure _] if the underlying storage fails. *)
val update : t -> Data.Note.t -> (Data.Note.t, error) result

(** [delete repo niceid] removes the note identified by [niceid].

    @return [Error Not_found _] if the note does not exist.
    @return [Error Backend_failure _] if the underlying storage fails. *)
val delete : t -> Data.Identifier.t -> (unit, error) result

(** [list repo ~statuses] returns notes filtered by [statuses].

    When [statuses] is empty, all notes except those with status [Archived] are returned. *)
val list :
  t ->
  statuses:Data.Note.status list ->
  (Data.Note.t list, error) result

(** [list_all repo] returns every note regardless of status, ordered by id. *)
val list_all : t -> (Data.Note.t list, error) result

(** [delete_all repo] removes every note from the table. *)
val delete_all : t -> (unit, error) result

(** [import repo ~id ~title ~content ?status ()] inserts a note with a
    caller-provided TypeId, allocating a fresh niceid. Used during rebuild
    from JSONL. [status] defaults to [Data.Note.Active]. *)
val import :
  t ->
  id:Data.Note.id ->
  title:Data.Title.t ->
  content:Data.Content.t ->
  ?status:Data.Note.status ->
  unit ->
  (Data.Note.t, error) result
