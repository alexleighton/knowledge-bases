module Root = Kbases.Repository.Root

let with_root f =
  match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
  | Ok root ->
      Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f root)
  | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)

let with_db f =
  let db = Sqlite3.db_open ":memory:" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () -> f db)

let query_db_raw = Test_common.query_db_raw
let query_rows_raw = Test_common.query_rows_raw
let query_count_raw = Test_common.query_count_raw
let query_db = Test_common.query_db
let query_rows = Test_common.query_rows
let query_count = Test_common.query_count
