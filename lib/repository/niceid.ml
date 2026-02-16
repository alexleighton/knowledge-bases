module Sql = Sqlite3

type t = {
  db        : Sql.db;
  namespace : string;
}

type error =
  | Backend_failure of string

let init ~db ~namespace =
  try
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
  with
  | Sql.Error msg -> Error (Backend_failure msg)

let allocate { db; namespace } typeid =
  let typeid_str = Data.Uuid.Typeid.to_string typeid in
  try
    match Sqlite.exec db "BEGIN IMMEDIATE" with
    | Error msg -> Error (Backend_failure msg)
    | Ok () ->
        let next_id =
          match
            Sqlite.with_stmt_single db
              "SELECT IFNULL(MAX(niceid), -1) FROM niceid WHERE namespace = ?;"
              [(1, Sql.Data.TEXT namespace)]
              (fun stmt -> Ok (Sql.column_int stmt 0 + 1))
          with
          | Ok id -> Ok id
          | Error Sqlite.No_row_found -> Ok 0
          | Error (Sqlite.Step_failed _ | Sqlite.Constraint_violation
                  | Sqlite.Bind_failed _ | Sqlite.Row_parse_failed _ as err) ->
              Error (Backend_failure (Sqlite.error_message err))
        in
        let result =
          match next_id with
          | Error _ as err -> err
          | Ok id ->
              let params = [
                (1, Sql.Data.TEXT typeid_str);
                (2, Sql.Data.TEXT namespace);
                (3, Sql.Data.INT (Int64.of_int id));
              ] in
              match Sqlite.with_stmt_cmd db
                "INSERT INTO niceid(typeid, namespace, niceid) VALUES (?, ?, ?);"
                params
              with
              | Ok () -> Ok (Data.Identifier.make namespace id)
              | Error (Sqlite.Step_failed _ | Sqlite.Constraint_violation
                      | Sqlite.Bind_failed _ | Sqlite.Row_parse_failed _
                      | Sqlite.No_row_found as err) ->
                  Error (Backend_failure (Sqlite.error_message err))
        in
        (match result with
         | Ok _ as ok -> ignore (Sqlite.commit db); ok
         | Error _ as err -> ignore (Sqlite.rollback db); err)
  with
  | Sql.Error msg -> Error (Backend_failure msg)
  | Invalid_argument msg -> Error (Backend_failure msg)
