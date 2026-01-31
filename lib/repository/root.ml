module Sql = Sqlite3

type t = {
  db     : Sql.db;
  niceid : Niceid.t;
  note   : Note.t;
}

let niceid t = t.niceid
let note t = t.note
let db t = t.db

let close t = ignore (Sql.db_close t.db)

let init ~db_file ~namespace =
  let db =
    try Sql.db_open db_file
    with Sql.Error msg -> failwith msg
  in
  let fail msg =
    ignore (Sql.db_close db);
    failwith msg
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
    | Error _ -> fail "Unexpected error: note init failed"
  in
  { db; niceid = niceid_repo; note = note_repo }

