module Sql = Sqlite3

module Make (E : Data.Entity.S) = struct
  type t = {
    db          : Sql.db;
    niceid_repo : Niceid.t;
  }

  type error =
    | Not_found of [ `Id of E.id | `Niceid of Data.Identifier.t ]
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

  let _entity_of_row stmt =
    let id_str     = Sql.column_text stmt 0 in
    let niceid_s   = Sql.column_text stmt 1 in
    let title      = Sql.column_text stmt 2 in
    let content    = Sql.column_text stmt 3 in
    let status_s   = Sql.column_text stmt 4 in
    let created_at = Data.Timestamp.make (Sql.column_int stmt 5) in
    let updated_at = Data.Timestamp.make (Sql.column_int stmt 6) in
    let typeid     = Data.Uuid.Typeid.of_string id_str in
    let niceid     = Data.Identifier.from_string niceid_s in
    let status     = E.status_from_string status_s in
    Ok (E.make typeid niceid (Data.Title.make title) (Data.Content.make content) status
          ~created_at ~updated_at)

  let _table = E.entity_name

  let _select_cols = "id, niceid, title, content, status, created_at, updated_at"

  let init ~db ~niceid_repo =
    try
      let create_sql =
        Printf.sprintf
          "CREATE TABLE IF NOT EXISTS %s (\
             id TEXT PRIMARY KEY,\
             niceid TEXT UNIQUE NOT NULL,\
             title TEXT NOT NULL,\
             content TEXT NOT NULL,\
             status TEXT NOT NULL,\
             created_at INTEGER NOT NULL,\
             updated_at INTEGER NOT NULL\
           );"
          _table
      in
      match exec_sql db create_sql with
      | Ok () -> Ok { db; niceid_repo }
      | Error _ as e -> e
    with
    | Sql.Error msg -> Error (Backend_failure msg)

  let _insert repo ~entity_id ~title ~content ~status ~created_at ~updated_at =
    let open Result.Syntax in
    let* niceid =
      Niceid.allocate repo.niceid_repo entity_id
      |> Result.map_error (function
        | Niceid.Backend_failure msg -> Backend_failure msg
        | Niceid.Not_found -> Backend_failure "niceid not found")
    in
    let entity = E.make entity_id niceid title content status ~created_at ~updated_at in
    let+ () =
      Sqlite.with_stmt_cmd repo.db
        (Printf.sprintf
           "INSERT INTO %s(id, niceid, title, content, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?);"
           _table)
        [
          (1, Sql.Data.TEXT (Data.Uuid.Typeid.to_string entity_id));
          (2, Sql.Data.TEXT (Data.Identifier.to_string niceid));
          (3, Sql.Data.TEXT (Data.Title.to_string (E.title entity)));
          (4, Sql.Data.TEXT (Data.Content.to_string (E.content entity)));
          (5, Sql.Data.TEXT (E.status_to_string (E.status entity)));
          (6, Sql.Data.INT (Int64.of_int (Data.Timestamp.to_epoch created_at)));
          (7, Sql.Data.INT (Int64.of_int (Data.Timestamp.to_epoch updated_at)));
        ]
      |> map_sqlite_error ~niceid:niceid
    in
    entity

  let create repo ~title ~content ?(status = E.default_status) ?(now = Data.Timestamp.now) () =
    let ts = now () in
    _insert repo ~entity_id:(E.make_id ()) ~title ~content ~status
      ~created_at:ts ~updated_at:ts

  let import repo ~id ~title ~content ?(status = E.default_status) ~created_at ~updated_at () =
    _insert repo ~entity_id:id ~title ~content ~status ~created_at ~updated_at

  let get repo id =
    Sqlite.with_stmt_single repo.db
      (Printf.sprintf "SELECT %s FROM %s WHERE id = ?;" _select_cols _table)
      [(1, Sql.Data.TEXT (Data.Uuid.Typeid.to_string id))]
      _entity_of_row
    |> map_sqlite_error ~id

  let get_by_niceid repo niceid =
    Sqlite.with_stmt_single repo.db
      (Printf.sprintf "SELECT %s FROM %s WHERE niceid = ?;" _select_cols _table)
      [(1, Sql.Data.TEXT (Data.Identifier.to_string niceid))]
      _entity_of_row
    |> map_sqlite_error ~niceid

  let update repo entity =
    let open Result.Syntax in
    let* () =
      Sqlite.with_stmt_cmd repo.db
        (Printf.sprintf
           "UPDATE %s SET niceid = ?, title = ?, content = ?, status = ?, \
            created_at = ?, updated_at = ? WHERE id = ?;"
           _table)
        [
          (1, Sql.Data.TEXT (Data.Identifier.to_string (E.niceid entity)));
          (2, Sql.Data.TEXT (Data.Title.to_string (E.title entity)));
          (3, Sql.Data.TEXT (Data.Content.to_string (E.content entity)));
          (4, Sql.Data.TEXT (E.status_to_string (E.status entity)));
          (5, Sql.Data.INT (Int64.of_int (Data.Timestamp.to_epoch (E.created_at entity))));
          (6, Sql.Data.INT (Int64.of_int (Data.Timestamp.to_epoch (E.updated_at entity))));
          (7, Sql.Data.TEXT (Data.Uuid.Typeid.to_string (E.id entity)));
        ]
      |> map_sqlite_error ~id:(E.id entity) ~niceid:(E.niceid entity)
    in
    let changes = Sql.changes repo.db in
    if changes = 0 then Error (Not_found (`Id (E.id entity))) else Ok entity

  let delete repo niceid =
    let open Result.Syntax in
    let* () =
      Sqlite.with_stmt_cmd repo.db
        (Printf.sprintf "DELETE FROM %s WHERE niceid = ?;" _table)
        [(1, Sql.Data.TEXT (Data.Identifier.to_string niceid))]
      |> map_sqlite_error ~niceid
    in
    let changes = Sql.changes repo.db in
    if changes = 0 then Error (Not_found (`Niceid niceid)) else Ok ()

  let list repo ~statuses =
    let sql, params =
      match statuses with
      | [] ->
          Printf.sprintf "SELECT %s FROM %s WHERE status != ? ORDER BY niceid;" _select_cols _table,
          [ (1, Sql.Data.TEXT (E.status_to_string E.default_excluded_status)) ]
      | statuses ->
          let placeholders =
            statuses
            |> List.mapi (fun idx _ -> Printf.sprintf "?%d" (idx + 1))
            |> String.concat ", "
          in
          let params =
            statuses
            |> List.mapi (fun idx status ->
                (idx + 1, Sql.Data.TEXT (E.status_to_string status)))
          in
          (Printf.sprintf
             "SELECT %s FROM %s WHERE status IN (%s) ORDER BY niceid;"
             _select_cols _table placeholders,
           params)
    in
    Sqlite.with_stmt repo.db sql params _entity_of_row
    |> map_sqlite_error

  let list_all repo =
    Sqlite.with_stmt repo.db
      (Printf.sprintf "SELECT %s FROM %s ORDER BY id;" _select_cols _table)
      []
      _entity_of_row
    |> map_sqlite_error

  let delete_all repo =
    Sqlite.with_stmt_cmd repo.db (Printf.sprintf "DELETE FROM %s;" _table) []
    |> map_sqlite_error
end
