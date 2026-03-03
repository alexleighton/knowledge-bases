module Sql = Sqlite3

type t = {
  db        : Sql.db;
  namespace : string;
}

type error =
  | Backend_failure of string

let map_sqlite_error result =
  Result.map_error
    (function
     | Sqlite.No_row_found -> Backend_failure "no row found"
     | Sqlite.Step_failed _ | Sqlite.Constraint_violation
     | Sqlite.Bind_failed _ | Sqlite.Row_parse_failed _ as err ->
         Backend_failure (Sqlite.error_message err))
    result

let map_no_row_to_zero = function
  | Error Sqlite.No_row_found -> Ok 0
  | Error (Sqlite.Step_failed _ as err)
  | Error (Sqlite.Constraint_violation as err)
  | Error (Sqlite.Bind_failed _ as err)
  | Error (Sqlite.Row_parse_failed _ as err) -> map_sqlite_error (Error err)
  | Ok _ as ok -> ok

let init ~db ~namespace =
  let create_sql =
    "CREATE TABLE IF NOT EXISTS niceid (\
     typeid TEXT PRIMARY KEY,\
     namespace TEXT NOT NULL,\
     niceid INTEGER NOT NULL\
    );"
  in
  match Sqlite.exec db create_sql with
  | Ok () -> Ok { db; namespace }
  | Error msg -> Error (Backend_failure msg)

let allocate { db; namespace } typeid =
  let open Result.Syntax in
  let typeid_str = Data.Uuid.Typeid.to_string typeid in
  Sqlite.with_savepoint db ~name:"alloc_niceid" ~on_begin_error:(fun msg -> Backend_failure msg)
    (fun () ->
       let* next_id =
         Sqlite.with_stmt_single db
           "SELECT IFNULL(MAX(niceid), -1) FROM niceid WHERE namespace = ?;"
           [(1, Sql.Data.TEXT namespace)]
           (fun stmt -> Ok (Sql.column_int stmt 0 + 1))
         |> map_no_row_to_zero
       in
       Sqlite.with_stmt_cmd db
         "INSERT INTO niceid(typeid, namespace, niceid) VALUES (?, ?, ?);"
         [
           (1, Sql.Data.TEXT typeid_str);
           (2, Sql.Data.TEXT namespace);
           (3, Sql.Data.INT (Int64.of_int next_id));
         ]
       |> map_sqlite_error
       |> Result.map (fun () -> Data.Identifier.make namespace next_id))

let delete_all { db; _ } =
  Sqlite.with_stmt_cmd db "DELETE FROM niceid;" []
  |> map_sqlite_error
