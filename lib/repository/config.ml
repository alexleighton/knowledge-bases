(** Configuration repository implementation.

    Provides a simple key/value store backed by the shared database so
    higher layers can persist settings such as the namespace. *)

module Sql = Sqlite3

type t = { db : Sql.db }

type error =
  | Not_found of string
  | Backend_failure of string

let create_table_sql =
  "CREATE TABLE IF NOT EXISTS config (\
   key TEXT PRIMARY KEY,\
   value TEXT NOT NULL\
  );"

let map_sqlite_error err = Backend_failure (Sqlite.error_message err)

let init ~db =
  try
    match Sqlite.exec db create_table_sql with
    | Ok () -> Ok { db }
    | Error msg -> Error (Backend_failure msg)
  with Sql.Error msg -> Error (Backend_failure msg)

let get repo key : (string, error) result =
  match
    Sqlite.with_stmt_single
      repo.db
      "SELECT value FROM config WHERE key = ?;"
      [ (1, Sql.Data.TEXT key) ]
      (fun stmt -> Ok (Sql.column_text stmt 0))
  with
  | Ok value -> Ok value
  | Error Sqlite.No_row_found -> Error (Not_found key)
  | Error (Sqlite.Step_failed _ | Sqlite.Constraint_violation
          | Sqlite.Bind_failed _ | Sqlite.Row_parse_failed _ as err) ->
      Error (map_sqlite_error err)

let set repo key value =
  match
    Sqlite.with_stmt_cmd
      repo.db
      "INSERT OR REPLACE INTO config(key, value) VALUES (?, ?);"
      [
        (1, Sql.Data.TEXT key);
        (2, Sql.Data.TEXT value);
      ]
  with
  | Ok () -> Ok ()
  | Error err -> Error (map_sqlite_error err)

let delete repo key =
  match
    Sqlite.with_stmt_cmd
      repo.db
      "DELETE FROM config WHERE key = ?;"
      [ (1, Sql.Data.TEXT key) ]
  with
  | Error err -> Error (map_sqlite_error err)
  | Ok () ->
      if Sql.changes repo.db = 0 then Error (Not_found key) else Ok ()
