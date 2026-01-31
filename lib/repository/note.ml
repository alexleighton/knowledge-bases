module Sql = Sqlite3

type t = {
  db           : Sql.db;
  niceid_repo  : Niceid.t;
}

type error =
  | Not_found of [ `Id of Data.Note.id | `Niceid of Data.Identifier.t ]
  | Duplicate_niceid of Data.Identifier.t
  | Backend_failure of string

let exec_sql db sql =
  Sqlite.exec db sql |> Result.map_error (fun msg -> Backend_failure msg)

let map_sqlite_error ?id ?niceid = Result.map_error (function
  | Sqlite.Constraint_violation ->
      (match niceid with
       | Some n -> Duplicate_niceid n
       | None -> Backend_failure "sqlite constraint violation")
  | Sqlite.No_row_found ->
      (match id, niceid with
       | Some id, _ -> Not_found (`Id id)
       | _, Some niceid -> Not_found (`Niceid niceid)
       | _ -> Backend_failure "sqlite no row found")
  | Sqlite.Step_failed msg -> Backend_failure msg
  | Sqlite.Bind_failed msg -> Backend_failure msg
  | Sqlite.Row_parse_failed msg -> Backend_failure msg
)

let _note_of_row stmt =
  let open Data in
  let id_str    = Sql.column_text stmt 0 in
  let niceid_s  = Sql.column_text stmt 1 in
  let title     = Sql.column_text stmt 2 in
  let content   = Sql.column_text stmt 3 in
  let typeid    = Uuid.Typeid.of_string id_str in
  let niceid    = Identifier.from_string niceid_s in
  Ok (Note.make typeid niceid title content)

let init ~db ~niceid_repo =
  try
    let create_sql =
      "CREATE TABLE IF NOT EXISTS note (\
         id TEXT PRIMARY KEY,\
         niceid TEXT UNIQUE NOT NULL,\
         title TEXT NOT NULL,\
         content TEXT NOT NULL\
       );"
    in
    match exec_sql db create_sql with
    | Ok () -> Ok { db; niceid_repo }
    | Error _ as e -> e
  with
  | Sql.Error msg -> Error (Backend_failure msg)

let create repo ~title ~content =
  let open Data in
  let open Result.Syntax in
  let note_id = Note.make_id () in
  let* niceid =
    Niceid.allocate repo.niceid_repo note_id
    |> Result.map_error (function Niceid.Backend_failure msg -> Backend_failure msg)
  in
  let note = Note.make note_id niceid title content in
  let+ () =
    Sqlite.with_stmt_cmd repo.db
      "INSERT INTO note(id, niceid, title, content) VALUES (?, ?, ?, ?);"
      [
        (1, Sql.Data.TEXT (Uuid.Typeid.to_string note_id));
        (2, Sql.Data.TEXT (Identifier.to_string niceid));
        (3, Sql.Data.TEXT (Note.title note));
        (4, Sql.Data.TEXT (Note.content note));
      ]
    |> map_sqlite_error ~niceid:niceid
  in
  note

let get repo id =
  Sqlite.with_stmt_single repo.db
    "SELECT id, niceid, title, content FROM note WHERE id = ?;"
    [(1, Sql.Data.TEXT (Data.Uuid.Typeid.to_string id))]
    _note_of_row
  |> map_sqlite_error ~id

let get_by_niceid repo niceid =
  Sqlite.with_stmt_single repo.db
    "SELECT id, niceid, title, content FROM note WHERE niceid = ?;"
    [(1, Sql.Data.TEXT (Data.Identifier.to_string niceid))]
    _note_of_row
  |> map_sqlite_error ~niceid

let update repo note =
  let open Result.Syntax in
  let* () =
    Sqlite.with_stmt_cmd repo.db
      "UPDATE note SET niceid = ?, title = ?, content = ? WHERE id = ?;"
      [
        (1, Sql.Data.TEXT (Data.Identifier.to_string (Data.Note.niceid note)));
        (2, Sql.Data.TEXT (Data.Note.title note));
        (3, Sql.Data.TEXT (Data.Note.content note));
        (4, Sql.Data.TEXT (Data.Uuid.Typeid.to_string (Data.Note.id note)));
      ]
    |> map_sqlite_error ~id:(Data.Note.id note) ~niceid:(Data.Note.niceid note)
  in
  let changes = Sql.changes repo.db in
  if changes = 0 then Error (Not_found (`Id (Data.Note.id note))) else Ok note

let delete repo niceid =
  let open Result.Syntax in
  let* () =
    Sqlite.with_stmt_cmd repo.db
      "DELETE FROM note WHERE niceid = ?;"
      [(1, Sql.Data.TEXT (Data.Identifier.to_string niceid))]
    |> map_sqlite_error ~niceid
  in
  let changes = Sql.changes repo.db in
  if changes = 0 then Error (Not_found (`Niceid niceid)) else Ok ()
