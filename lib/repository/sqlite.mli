(** Lightweight helpers for issuing raw SQL against SQLite repositories. *)

(** Error type for statement operations. *)
type error =
  | Step_failed of string
  | Constraint_violation
  | Bind_failed of string
  | Row_parse_failed of string
  | No_row_found

(** [error_message err] returns a human-readable description of [err]. *)
val error_message : error -> string

(** [exec db sql] runs [sql] against [db] and returns an [Error msg] when sqlite
    does not report [OK]. *)
val exec : Sqlite3.db -> string -> (unit, string) result

(** [commit db] attempts to commit the current transaction on [db]. *)
val commit : Sqlite3.db -> (unit, string) result

(** [rollback db] attempts to roll back the current transaction on [db]. *)
val rollback : Sqlite3.db -> (unit, string) result

(** [with_transaction db ~on_begin_error f] begins a transaction, runs [f],
    commits on [Ok], rolls back on [Error], and returns the result of [f].
    Maps a begin failure string via [on_begin_error]. *)
val with_transaction :
  Sqlite3.db ->
  on_begin_error:(string -> 'e) ->
  (unit -> ('a, 'e) result) ->
  ('a, 'e) result

(** [with_stmt db sql params row_fn] prepares [sql] on [db], binds [params],
    steps through all rows, applies [row_fn] to build a list, and always
    finalizes the statement. Returns [Error] on bind, step, or row parse failures. *)
val with_stmt :
  Sqlite3.db ->
  string ->
  (int * Sqlite3.Data.t) list ->
  (Sqlite3.stmt -> ('a, error) result) ->
  ('a list, error) result

(** [with_stmt_single db sql params row_fn] prepares [sql] on [db], binds [params],
    steps once, applies [row_fn] if a row exists, and always finalizes the statement.
    Returns [Ok a] if row found and parsed successfully, [Error No_row_found] if no row.
    Returns [Error] on bind, step, or row parse failures. *)
val with_stmt_single :
  Sqlite3.db ->
  string ->
  (int * Sqlite3.Data.t) list ->
  (Sqlite3.stmt -> ('a, error) result) ->
  ('a, error) result

(** [with_stmt_cmd db sql params] prepares [sql] on [db], binds [params],
    executes the command (expecting DONE), and always finalizes the statement.
    Useful for INSERT, UPDATE, DELETE. Returns [Error] on bind or step failures. *)
val with_stmt_cmd :
  Sqlite3.db ->
  string ->
  (int * Sqlite3.Data.t) list ->
  (unit, error) result
