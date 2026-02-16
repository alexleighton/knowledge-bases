module Sql = Sqlite3

type t = {
  db     : Sql.db;
  niceid : Niceid.t;
  note   : Note.t;
  config : Config.t;
}

type error = Backend_failure of string

let niceid t = t.niceid
let note t = t.note
let config t = t.config
let db t = t.db

let close t = ignore (Sql.db_close t.db)

let init ~db_file ~namespace =
  try
    let db = Sql.db_open db_file in
    let fail msg =
      ignore (Sql.db_close db);
      failwith msg
    in
    let config_repo =
      match Config.init ~db with
      | Ok repo -> repo
      | Error (Config.Backend_failure msg) -> fail msg
      | Error (Config.Not_found key) -> fail ("Config table missing key: " ^ key)
    in
    let namespace =
      match namespace with
      | Some ns -> ns
      | None -> (
          match Config.get config_repo "namespace" with
          | Ok ns -> ns
          | Error (Config.Not_found _) ->
              fail "No namespace configured. Set the 'namespace' config key."
          | Error (Config.Backend_failure msg) -> fail msg)
    in
    let niceid_repo =
      match Niceid.init ~db ~namespace with
      | Ok repo -> repo
      | Error (Niceid.Backend_failure msg) -> fail msg
    in
    let note_repo =
      match Note.init ~db ~niceid_repo with
      | Ok repo -> repo
      | Error (Note.Backend_failure msg) -> fail msg
      | Error (Note.Not_found _ | Note.Duplicate_niceid _) ->
          fail "Unexpected error during note repository initialization"
    in
    Ok {
      db;
      niceid = niceid_repo;
      note = note_repo;
      config = config_repo;
    }
  with
  | Failure msg -> Error (Backend_failure msg)
  | Sql.Error msg -> Error (Backend_failure msg)
