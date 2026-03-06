module Root = Kbases.Repository.Root
module Sqlite = Kbases.Repository.Sqlite

let with_root f =
  match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
  | Ok root ->
      Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f root)
  | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)

let with_db f =
  let db = Sqlite3.db_open ":memory:" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () -> f db)

let query_db_raw db sql params row_printer =
  match Sqlite.with_stmt db sql params (fun stmt -> Ok (row_printer stmt)) with
  | Ok rows -> List.iter print_endline rows
  | Error err -> Printf.printf "query error: %s\n" (Sqlite.error_message err)

let query_rows_raw db sql params =
  query_db_raw db sql params (fun stmt ->
    let n = Sqlite3.data_count stmt in
    List.init n (fun i -> Sqlite3.column_text stmt i)
    |> String.concat "|")

let query_count_raw db table =
  query_db_raw db
    (Printf.sprintf "SELECT count(*) FROM %s" table)
    []
    (fun stmt -> Printf.sprintf "%s=%s" table (Sqlite3.column_text stmt 0))

let query_db root sql params row_printer =
  query_db_raw (Root.db root) sql params row_printer

let query_rows root sql params =
  query_rows_raw (Root.db root) sql params

let query_count root table =
  query_count_raw (Root.db root) table
