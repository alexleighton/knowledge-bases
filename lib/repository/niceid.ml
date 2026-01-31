module Sql = Sqlite3

type t = {
  db        : Sql.db;
  namespace : string;
}

type error =
  | Backend_failure of string

let map_backend_error =
  Result.map_error (fun msg -> Backend_failure msg)

let map_sqlite_error = function
  | Sqlite.Step_failed msg -> Error (Backend_failure msg)
  | Sqlite.Bind_failed msg -> Error (Backend_failure msg)
  | Sqlite.Row_parse_failed msg -> Error (Backend_failure msg)
  | Sqlite.Constraint_violation -> Error (Backend_failure "niceid constraint violation")
  | Sqlite.No_row_found -> Error (Backend_failure "no row found")

let exec_sql db sql = Sqlite.exec db sql |> map_backend_error

let commit_sql db = Sqlite.commit db |> map_backend_error

let rollback_sql db = Sqlite.rollback db |> map_backend_error

let init ~db ~namespace =
  try
    let create_sql =
      "CREATE TABLE IF NOT EXISTS niceid (\
       typeid TEXT PRIMARY KEY,\
       niceid INTEGER NOT NULL\
      );"
    in
    match exec_sql db create_sql with
    | Ok () -> Ok { db; namespace }
    | Error _ as e -> e
  with
  | Sql.Error msg -> Error (Backend_failure msg)

let allocate { db; namespace; _ } typeid =
  let rollback () = ignore (rollback_sql db) in
  let commit () = ignore (commit_sql db) in
  let typeid_str = Data.Uuid.Typeid.to_string typeid in
  let run () =
    match exec_sql db "BEGIN IMMEDIATE" with
    | Error _ as e -> e
    | Ok () ->
        (* Get the next ID *)
        let get_max_id stmt =
          let current = Sql.column_int stmt 0 in
          Ok (current + 1)
        in
        let next_id =
          match Sqlite.with_stmt_single db "SELECT IFNULL(MAX(niceid), -1) FROM niceid;" [] get_max_id with
          | Ok id -> id
          | Error Sqlite.No_row_found -> 0
          | Error _ ->
              rollback ();
              raise (Failure "Failed to get max niceid")
        in
        (* Insert the new niceid *)
        let params = [
          (1, Sql.Data.TEXT typeid_str);
          (2, Sql.Data.INT (Int64.of_int next_id));
        ] in
        match Sqlite.with_stmt_cmd db "INSERT INTO niceid(typeid, niceid) VALUES (?, ?);" params with
        | Ok () ->
            commit ();
            Ok (Data.Identifier.make namespace next_id)
        | Error Sqlite.Constraint_violation ->
            rollback ();
            Error (Backend_failure "niceid constraint violation")
        | Error e ->
            rollback ();
            map_sqlite_error e
  in
  try run () with
  | Sql.Error msg -> Error (Backend_failure msg)
  | Invalid_argument msg -> Error (Backend_failure msg)
  | Failure msg -> Error (Backend_failure msg)
