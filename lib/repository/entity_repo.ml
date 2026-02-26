module Sql = Sqlite3

module type ENTITY = sig
  include Data.Entity.S with type id = Data.Uuid.Typeid.t

  val table_name : string
  val default_status : status
  val default_excluded_status : status
  val id_to_string : id -> string
  val id_of_string : string -> id
end

type error =
  | Not_found of [ `Id of Data.Uuid.Typeid.t | `Niceid of Data.Identifier.t ]
  | Duplicate_niceid of Data.Identifier.t
  | Backend_failure of string

module Make (E : ENTITY) = struct
  type t = {
    db          : Sql.db;
    niceid_repo : Niceid.t;
  }

  type nonrec error = error =
    | Not_found of [ `Id of Data.Uuid.Typeid.t | `Niceid of Data.Identifier.t ]
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
    let id_str   = Sql.column_text stmt 0 in
    let niceid_s = Sql.column_text stmt 1 in
    let title    = Sql.column_text stmt 2 in
    let content  = Sql.column_text stmt 3 in
    let status_s = Sql.column_text stmt 4 in
    let typeid   = E.id_of_string id_str in
    let niceid   = Data.Identifier.from_string niceid_s in
    let status   = E.status_from_string status_s in
    Ok (E.make typeid niceid (Data.Title.make title) (Data.Content.make content) status)

  let init ~db ~niceid_repo =
    try
      let create_sql =
        Printf.sprintf
          "CREATE TABLE IF NOT EXISTS %s (\
             id TEXT PRIMARY KEY,\
             niceid TEXT UNIQUE NOT NULL,\
             title TEXT NOT NULL,\
             content TEXT NOT NULL,\
             status TEXT NOT NULL\
           );"
          E.table_name
      in
      match exec_sql db create_sql with
      | Ok () -> Ok { db; niceid_repo }
      | Error _ as e -> e
    with
    | Sql.Error msg -> Error (Backend_failure msg)

  let create repo ~title ~content ?(status = E.default_status) () =
    let open Result.Syntax in
    let entity_id = E.make_id () in
    let* niceid =
      Niceid.allocate repo.niceid_repo entity_id
      |> Result.map_error (function Niceid.Backend_failure msg -> Backend_failure msg)
    in
    let entity = E.make entity_id niceid title content status in
    let+ () =
      Sqlite.with_stmt_cmd repo.db
        (Printf.sprintf
           "INSERT INTO %s(id, niceid, title, content, status) VALUES (?, ?, ?, ?, ?);"
           E.table_name)
        [
          (1, Sql.Data.TEXT (E.id_to_string entity_id));
          (2, Sql.Data.TEXT (Data.Identifier.to_string niceid));
          (3, Sql.Data.TEXT (Data.Title.to_string (E.title entity)));
          (4, Sql.Data.TEXT (Data.Content.to_string (E.content entity)));
          (5, Sql.Data.TEXT (E.status_to_string (E.status entity)));
        ]
      |> map_sqlite_error ~niceid:niceid
    in
    entity

  let get repo id =
    Sqlite.with_stmt_single repo.db
      (Printf.sprintf
         "SELECT id, niceid, title, content, status FROM %s WHERE id = ?;"
         E.table_name)
      [(1, Sql.Data.TEXT (E.id_to_string id))]
      _entity_of_row
    |> map_sqlite_error ~id

  let get_by_niceid repo niceid =
    Sqlite.with_stmt_single repo.db
      (Printf.sprintf
         "SELECT id, niceid, title, content, status FROM %s WHERE niceid = ?;"
         E.table_name)
      [(1, Sql.Data.TEXT (Data.Identifier.to_string niceid))]
      _entity_of_row
    |> map_sqlite_error ~niceid

  let update repo entity =
    let open Result.Syntax in
    let* () =
      Sqlite.with_stmt_cmd repo.db
        (Printf.sprintf
           "UPDATE %s SET niceid = ?, title = ?, content = ?, status = ? WHERE id = ?;"
           E.table_name)
        [
          (1, Sql.Data.TEXT (Data.Identifier.to_string (E.niceid entity)));
          (2, Sql.Data.TEXT (Data.Title.to_string (E.title entity)));
          (3, Sql.Data.TEXT (Data.Content.to_string (E.content entity)));
          (4, Sql.Data.TEXT (E.status_to_string (E.status entity)));
          (5, Sql.Data.TEXT (E.id_to_string (E.id entity)));
        ]
      |> map_sqlite_error ~id:(E.id entity) ~niceid:(E.niceid entity)
    in
    let changes = Sql.changes repo.db in
    if changes = 0 then Error (Not_found (`Id (E.id entity))) else Ok entity

  let delete repo niceid =
    let open Result.Syntax in
    let* () =
      Sqlite.with_stmt_cmd repo.db
        (Printf.sprintf "DELETE FROM %s WHERE niceid = ?;" E.table_name)
        [(1, Sql.Data.TEXT (Data.Identifier.to_string niceid))]
      |> map_sqlite_error ~niceid
    in
    let changes = Sql.changes repo.db in
    if changes = 0 then Error (Not_found (`Niceid niceid)) else Ok ()

  let list repo ~statuses =
    let sql, params =
      match statuses with
      | [] ->
          Printf.sprintf
            "SELECT id, niceid, title, content, status \
             FROM %s WHERE status != ? ORDER BY niceid;"
            E.table_name,
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
             "SELECT id, niceid, title, content, status \
              FROM %s WHERE status IN (%s) ORDER BY niceid;"
             E.table_name placeholders,
           params)
    in
    Sqlite.with_stmt repo.db sql params _entity_of_row
    |> map_sqlite_error
end
