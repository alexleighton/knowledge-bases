module Root = Kbases.Repository.Root
module Sqlite = Kbases.Repository.Sqlite

let rec rm_rf path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter
        (fun entry -> rm_rf (Filename.concat path entry))
        (Sys.readdir path);
      Unix.rmdir path
    end else
      Sys.remove path

let create_git_root prefix =
  let root = Filename.temp_dir prefix "" in
  Unix.mkdir (Filename.concat root ".git") 0o755;
  root

let with_git_root prefix f =
  let root = create_git_root prefix in
  Fun.protect ~finally:(fun () -> rm_rf root) (fun () -> f root)

let with_temp_dir prefix f =
  let dir = Filename.temp_dir prefix "" in
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f dir)

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
