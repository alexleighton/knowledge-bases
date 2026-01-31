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

(** [create repo ~title ~content] stores a new note, generating identifiers
    for it.

    @return the newly stored note on success.
    @raise Invalid_argument if the generated values fail {!Note.make}
      validation.
    @return [Error Duplicate_niceid _] if the generated nice id already exists.
    @return [Error Backend_failure _] if the underlying storage fails. *)
val create :
  t ->
  title:string ->
  content:string ->
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
