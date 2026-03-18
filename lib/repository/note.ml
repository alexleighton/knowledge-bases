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

let _note_of_row stmt =
  let id_str    = Sql.column_text stmt 0 in
  let niceid_s  = Sql.column_text stmt 1 in
  let title     = Sql.column_text stmt 2 in
  let content   = Sql.column_text stmt 3 in
  let status_s  = Sql.column_text stmt 4 in
  let created_at = Data.Timestamp.make (Sql.column_int stmt 5) in
  let updated_at = Data.Timestamp.make (Sql.column_int stmt 6) in
  let typeid    = Data.Uuid.Typeid.of_string id_str in
  let niceid    = Data.Identifier.from_string niceid_s in
  let status    = Data.Note.status_from_string status_s in
  Ok (Data.Note.make typeid niceid (Data.Title.make title) (Data.Content.make content) status
        ~created_at ~updated_at)

let _select_cols = "id, niceid, title, content, status, created_at, updated_at"

let init ~db ~niceid_repo =
  try
    let create_sql =
      "CREATE TABLE IF NOT EXISTS note (\
         id TEXT PRIMARY KEY,\
         niceid TEXT UNIQUE NOT NULL,\
         title TEXT NOT NULL,\
         content TEXT NOT NULL,\
         status TEXT NOT NULL,\
         created_at INTEGER NOT NULL,\
         updated_at INTEGER NOT NULL\
       );"
    in
    match exec_sql db create_sql with
    | Ok () -> Ok { db; niceid_repo }
    | Error _ as e -> e
  with
  | Sql.Error msg -> Error (Backend_failure msg)


let _insert repo ~note_id ~title ~content ~status ~created_at ~updated_at =
  let open Result.Syntax in
  let* niceid =
    Niceid.allocate repo.niceid_repo note_id
    |> Result.map_error (function
      | Niceid.Backend_failure msg -> Backend_failure msg
      | Niceid.Not_found -> Backend_failure "niceid not found")
  in
  let note = Data.Note.make note_id niceid title content status ~created_at ~updated_at in
  let+ () =
    Sqlite.with_stmt_cmd repo.db
      "INSERT INTO note(id, niceid, title, content, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?);"
      [
        (1, Sql.Data.TEXT (Data.Uuid.Typeid.to_string note_id));
        (2, Sql.Data.TEXT (Data.Identifier.to_string niceid));
        (3, Sql.Data.TEXT (Data.Title.to_string (Data.Note.title note)));
        (4, Sql.Data.TEXT (Data.Content.to_string (Data.Note.content note)));
        (5, Sql.Data.TEXT (Data.Note.status_to_string (Data.Note.status note)));
        (6, Sql.Data.INT (Int64.of_int (Data.Timestamp.to_epoch created_at)));
        (7, Sql.Data.INT (Int64.of_int (Data.Timestamp.to_epoch updated_at)));
      ]
    |> map_sqlite_error ~niceid:niceid
  in
  note

let create repo ~title ~content ?(status = Data.Note.Active) ?(now = Data.Timestamp.now) () =
  let ts = now () in
  _insert repo ~note_id:(Data.Note.make_id ()) ~title ~content ~status
    ~created_at:ts ~updated_at:ts

let import repo ~id ~title ~content ?(status = Data.Note.Active) ~created_at ~updated_at () =
  _insert repo ~note_id:id ~title ~content ~status ~created_at ~updated_at

let get repo id =
  Sqlite.with_stmt_single repo.db
    (Printf.sprintf "SELECT %s FROM note WHERE id = ?;" _select_cols)
    [(1, Sql.Data.TEXT (Data.Uuid.Typeid.to_string id))]
    _note_of_row
  |> map_sqlite_error ~id

let get_by_niceid repo niceid =
  Sqlite.with_stmt_single repo.db
    (Printf.sprintf "SELECT %s FROM note WHERE niceid = ?;" _select_cols)
    [(1, Sql.Data.TEXT (Data.Identifier.to_string niceid))]
    _note_of_row
  |> map_sqlite_error ~niceid

let update repo note =
  let open Result.Syntax in
  let* () =
    Sqlite.with_stmt_cmd repo.db
      "UPDATE note SET niceid = ?, title = ?, content = ?, status = ?, \
       created_at = ?, updated_at = ? WHERE id = ?;"
      [
        (1, Sql.Data.TEXT (Data.Identifier.to_string (Data.Note.niceid note)));
        (2, Sql.Data.TEXT (Data.Title.to_string   (Data.Note.title   note)));
        (3, Sql.Data.TEXT (Data.Content.to_string (Data.Note.content note)));
        (4, Sql.Data.TEXT (Data.Note.status_to_string (Data.Note.status note)));
        (5, Sql.Data.INT (Int64.of_int (Data.Timestamp.to_epoch (Data.Note.created_at note))));
        (6, Sql.Data.INT (Int64.of_int (Data.Timestamp.to_epoch (Data.Note.updated_at note))));
        (7, Sql.Data.TEXT (Data.Uuid.Typeid.to_string (Data.Note.id note)));
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

let list repo ~statuses =
  let sql, params =
    match statuses with
    | [] ->
        Printf.sprintf "SELECT %s FROM note WHERE status != ? ORDER BY niceid;" _select_cols,
        [ (1, Sql.Data.TEXT (Data.Note.status_to_string Data.Note.Archived)) ]
    | statuses ->
        let placeholders =
          statuses
          |> List.mapi (fun idx _ -> Printf.sprintf "?%d" (idx + 1))
          |> String.concat ", "
        in
        let params =
          statuses
          |> List.mapi (fun idx status ->
              (idx + 1, Sql.Data.TEXT (Data.Note.status_to_string status)))
        in
        (Printf.sprintf
           "SELECT %s FROM note WHERE status IN (%s) ORDER BY niceid;"
           _select_cols placeholders,
         params)
  in
  Sqlite.with_stmt repo.db sql params _note_of_row
  |> map_sqlite_error

let list_all repo =
  Sqlite.with_stmt repo.db
    (Printf.sprintf "SELECT %s FROM note ORDER BY id;" _select_cols)
    []
    _note_of_row
  |> map_sqlite_error

let delete_all repo =
  Sqlite.with_stmt_cmd repo.db "DELETE FROM note;" []
  |> map_sqlite_error
