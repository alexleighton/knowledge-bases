module Sql = Sqlite3

type t = { db : Sql.db }

type error =
  | Duplicate
  | Backend_failure of string

let exec_sql db sql =
  Sqlite.exec db sql |> Result.map_error (fun msg -> Backend_failure msg)

let map_sqlite_error r = Result.map_error (function
  | Sqlite.Constraint_violation -> Duplicate
  | Sqlite.No_row_found -> Backend_failure "no row found"
  | Sqlite.Step_failed _ | Sqlite.Bind_failed _
  | Sqlite.Row_parse_failed _ as err ->
      Backend_failure (Sqlite.error_message err)
) r

let init ~db =
  let create_sql =
    "CREATE TABLE IF NOT EXISTS relation (\
       source TEXT NOT NULL,\
       target TEXT NOT NULL,\
       kind TEXT NOT NULL,\
       bidirectional INTEGER NOT NULL,\
       PRIMARY KEY (source, target, kind)\
     );"
  in
  match exec_sql db create_sql with
  | Ok () -> Ok { db }
  | Error _ as e -> e

let _reverse_exists repo rel =
  let source = Data.Uuid.Typeid.to_string (Data.Relation.target rel) in
  let target = Data.Uuid.Typeid.to_string (Data.Relation.source rel) in
  let kind = Data.Relation_kind.to_string (Data.Relation.kind rel) in
  match
    Sqlite.with_stmt_single repo.db
      "SELECT 1 FROM relation WHERE source = ? AND target = ? AND kind = ?;"
      [
        (1, Sql.Data.TEXT source);
        (2, Sql.Data.TEXT target);
        (3, Sql.Data.TEXT kind);
      ]
      (fun _stmt -> Ok ())
  with
  | Ok () -> Ok true
  | Error Sqlite.No_row_found -> Ok false
  | Error (Sqlite.Step_failed _ | Sqlite.Bind_failed _
          | Sqlite.Row_parse_failed _ | Sqlite.Constraint_violation as err) ->
      Error (Backend_failure (Sqlite.error_message err))

let create repo rel =
  let open Result.Syntax in
  let* reverse =
    if Data.Relation.is_bidirectional rel then _reverse_exists repo rel
    else Ok false
  in
  if reverse then Error Duplicate
  else
    let source = Data.Uuid.Typeid.to_string (Data.Relation.source rel) in
    let target = Data.Uuid.Typeid.to_string (Data.Relation.target rel) in
    let kind = Data.Relation_kind.to_string (Data.Relation.kind rel) in
    let bidi = if Data.Relation.is_bidirectional rel then 1 else 0 in
    Sqlite.with_stmt_cmd repo.db
      "INSERT INTO relation(source, target, kind, bidirectional) \
       VALUES (?, ?, ?, ?);"
      [
        (1, Sql.Data.TEXT source);
        (2, Sql.Data.TEXT target);
        (3, Sql.Data.TEXT kind);
        (4, Sql.Data.INT (Int64.of_int bidi));
      ]
    |> map_sqlite_error
    |> Result.map (fun () -> rel)

let _relation_of_row stmt =
  let source = Data.Uuid.Typeid.of_string (Sql.column_text stmt 0) in
  let target = Data.Uuid.Typeid.of_string (Sql.column_text stmt 1) in
  let kind = Data.Relation_kind.make (Sql.column_text stmt 2) in
  let bidirectional = Sql.column_int stmt 3 <> 0 in
  Ok (Data.Relation.make ~source ~target ~kind ~bidirectional)

let list_all repo =
  Sqlite.with_stmt repo.db
    "SELECT source, target, kind, bidirectional \
     FROM relation ORDER BY source, target, kind;"
    []
    _relation_of_row
  |> map_sqlite_error

let find_by_source repo typeid =
  let id = Data.Uuid.Typeid.to_string typeid in
  Sqlite.with_stmt repo.db
    "SELECT source, target, kind, bidirectional \
     FROM relation WHERE source = ? ORDER BY target, kind;"
    [(1, Sql.Data.TEXT id)]
    _relation_of_row
  |> map_sqlite_error

let find_by_target repo typeid =
  let id = Data.Uuid.Typeid.to_string typeid in
  Sqlite.with_stmt repo.db
    "SELECT source, target, kind, bidirectional \
     FROM relation WHERE target = ? ORDER BY source, kind;"
    [(1, Sql.Data.TEXT id)]
    _relation_of_row
  |> map_sqlite_error

let delete_all repo =
  Sqlite.with_stmt_cmd repo.db "DELETE FROM relation;" []
  |> map_sqlite_error
