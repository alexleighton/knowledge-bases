module Root = Kbases.Repository.Root
module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo
module Sqlite = Kbases.Repository.Sqlite
module Identifier = Kbases.Data.Identifier

let create_git_root prefix =
  let root = Filename.temp_dir prefix "" in
  Unix.mkdir (Filename.concat root ".git") 0o755;
  root

let starts_with s prefix =
  let s_len = String.length s in
  let p_len = String.length prefix in
  s_len >= p_len && String.sub s 0 p_len = prefix

let normalize path =
  try Unix.realpath path with
  | Unix.Unix_error _ -> path

let with_chdir dir f =
  let original = Sys.getcwd () in
  Fun.protect ~finally:(fun () -> Sys.chdir original) (fun () -> Sys.chdir dir; f ())

let with_root db_file f =
  match Root.init ~db_file ~namespace:None with
  | Error (Root.Backend_failure msg) -> Printf.printf "root open failed: %s\n" msg
  | Ok opened ->
      Fun.protect ~finally:(fun () -> Root.close opened) (fun () -> f opened)

let unwrap_note_repo = function
  | Ok v -> v
  | Error (NoteRepo.Backend_failure msg) -> failwith ("backend failure: " ^ msg)
  | Error (NoteRepo.Duplicate_niceid niceid) ->
      failwith ("duplicate niceid: " ^ Identifier.to_string niceid)
  | Error (NoteRepo.Not_found _) -> failwith "note not found"

let unwrap_todo_repo = function
  | Ok v -> v
  | Error (TodoRepo.Backend_failure msg) -> failwith ("backend failure: " ^ msg)
  | Error (TodoRepo.Duplicate_niceid niceid) ->
      failwith ("duplicate niceid: " ^ Identifier.to_string niceid)
  | Error (TodoRepo.Not_found _) -> failwith "todo not found"

let query_db root sql params row_printer =
  let db = Root.db root in
  match Sqlite.with_stmt db sql params (fun stmt -> Ok (row_printer stmt)) with
  | Ok rows -> List.iter print_endline rows
  | Error err -> Printf.printf "query error: %s\n" (Sqlite.error_message err)

let query_rows root sql params =
  query_db root sql params (fun stmt ->
    let n = Sqlite3.data_count stmt in
    List.init n (fun i -> Sqlite3.column_text stmt i)
    |> String.concat "|")

let query_count root table =
  query_db root
    (Printf.sprintf "SELECT count(*) FROM %s" table)
    []
    (fun stmt -> Printf.sprintf "%s=%s" table (Sqlite3.column_text stmt 0))
