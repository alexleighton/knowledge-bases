module Sql = Sqlite3

type t = {
  db          : Sql.db;
  niceid_repo : Niceid.t;
}

type error =
  | Not_found of [ `Id of Data.Todo.id | `Niceid of Data.Identifier.t ]
  | Duplicate_niceid of Data.Identifier.t
  | Backend_failure of string

let exec_sql db sql =
  Sqlite.exec db sql |> Result.map_error (fun msg -> Backend_failure msg)

let map_sqlite_error ?id ?niceid = Result.map_error (function
  | Sqlite.Constraint_violation ->
      (match niceid with
       | Some n -> Duplicate_niceid n
       | None -> Backend_failure "constraint violation")
  | Sqlite.No_row_found ->
      (match id, niceid with
       | Some id, _ -> Not_found (`Id id)
       | _, Some niceid -> Not_found (`Niceid niceid)
       | _ -> Backend_failure "no row found")
  | Sqlite.Step_failed _ | Sqlite.Bind_failed _
  | Sqlite.Row_parse_failed _ as err ->
      Backend_failure (Sqlite.error_message err)
)

let _todo_of_row stmt =
  let id_str = Sql.column_text stmt 0 in
  let niceid_s = Sql.column_text stmt 1 in
  let title = Sql.column_text stmt 2 in
  let content = Sql.column_text stmt 3 in
  let status_s = Sql.column_text stmt 4 in
  let typeid = Data.Uuid.Typeid.of_string id_str in
  let niceid = Data.Identifier.from_string niceid_s in
  let status = Data.Todo.status_from_string status_s in
  Ok (Data.Todo.make typeid niceid (Data.Title.make title) (Data.Content.make content) status)

let init ~db ~niceid_repo =
  try
    let create_sql =
      "CREATE TABLE IF NOT EXISTS todo (\
         id TEXT PRIMARY KEY,\
         niceid TEXT UNIQUE NOT NULL,\
         title TEXT NOT NULL,\
         content TEXT NOT NULL,\
         status TEXT NOT NULL\
       );"
    in
    match exec_sql db create_sql with
    | Ok () -> Ok { db; niceid_repo }
    | Error _ as e -> e
  with
  | Sql.Error msg -> Error (Backend_failure msg)

let create repo ~title ~content ?(status = Data.Todo.Open) () =
  let open Result.Syntax in
  let todo_id = Data.Todo.make_id () in
  let* niceid =
    Niceid.allocate repo.niceid_repo todo_id
    |> Result.map_error (function Niceid.Backend_failure msg -> Backend_failure msg)
  in
  let todo = Data.Todo.make todo_id niceid title content status in
  let+ () =
    Sqlite.with_stmt_cmd repo.db
      "INSERT INTO todo(id, niceid, title, content, status) VALUES (?, ?, ?, ?, ?);"
      [
        (1, Sql.Data.TEXT (Data.Uuid.Typeid.to_string todo_id));
        (2, Sql.Data.TEXT (Data.Identifier.to_string niceid));
        (3, Sql.Data.TEXT (Data.Title.to_string (Data.Todo.title todo)));
        (4, Sql.Data.TEXT (Data.Content.to_string (Data.Todo.content todo)));
        (5, Sql.Data.TEXT (Data.Todo.status_to_string (Data.Todo.status todo)));
      ]
    |> map_sqlite_error ~niceid:niceid
  in
  todo

let get repo id =
  Sqlite.with_stmt_single repo.db
    "SELECT id, niceid, title, content, status FROM todo WHERE id = ?;"
    [(1, Sql.Data.TEXT (Data.Uuid.Typeid.to_string id))]
    _todo_of_row
  |> map_sqlite_error ~id

let get_by_niceid repo niceid =
  Sqlite.with_stmt_single repo.db
    "SELECT id, niceid, title, content, status FROM todo WHERE niceid = ?;"
    [(1, Sql.Data.TEXT (Data.Identifier.to_string niceid))]
    _todo_of_row
  |> map_sqlite_error ~niceid

let update repo todo =
  let open Result.Syntax in
  let* () =
    Sqlite.with_stmt_cmd repo.db
      "UPDATE todo SET niceid = ?, title = ?, content = ?, status = ? WHERE id = ?;"
      [
        (1, Sql.Data.TEXT (Data.Identifier.to_string (Data.Todo.niceid todo)));
        (2, Sql.Data.TEXT (Data.Title.to_string (Data.Todo.title todo)));
        (3, Sql.Data.TEXT (Data.Content.to_string (Data.Todo.content todo)));
        (4, Sql.Data.TEXT (Data.Todo.status_to_string (Data.Todo.status todo)));
        (5, Sql.Data.TEXT (Data.Uuid.Typeid.to_string (Data.Todo.id todo)));
      ]
    |> map_sqlite_error ~id:(Data.Todo.id todo) ~niceid:(Data.Todo.niceid todo)
  in
  let changes = Sql.changes repo.db in
  if changes = 0 then Error (Not_found (`Id (Data.Todo.id todo))) else Ok todo

let delete repo niceid =
  let open Result.Syntax in
  let* () =
    Sqlite.with_stmt_cmd repo.db
      "DELETE FROM todo WHERE niceid = ?;"
      [(1, Sql.Data.TEXT (Data.Identifier.to_string niceid))]
    |> map_sqlite_error ~niceid
  in
  let changes = Sql.changes repo.db in
  if changes = 0 then Error (Not_found (`Niceid niceid)) else Ok ()

let list repo ~statuses =
  let sql, params =
    match statuses with
    | [] ->
        "SELECT id, niceid, title, content, status \
         FROM todo WHERE status != ? ORDER BY niceid;",
        [ (1, Sql.Data.TEXT (Data.Todo.status_to_string Data.Todo.Done)) ]
    | statuses ->
        let placeholders =
          statuses
          |> List.mapi (fun idx _ -> Printf.sprintf "?%d" (idx + 1))
          |> String.concat ", "
        in
        let params =
          statuses
          |> List.mapi (fun idx status ->
              (idx + 1, Sql.Data.TEXT (Data.Todo.status_to_string status)))
        in
        (Printf.sprintf
           "SELECT id, niceid, title, content, status \
            FROM todo WHERE status IN (%s) ORDER BY niceid;"
           placeholders,
         params)
  in
  Sqlite.with_stmt repo.db sql params _todo_of_row
  |> map_sqlite_error
