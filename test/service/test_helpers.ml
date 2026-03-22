module Root = Kbases.Repository.Root
module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo
module Sqlite = Kbases.Repository.Sqlite
module Identifier = Kbases.Data.Identifier
module ItemService = Kbases.Service.Item_service

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

let pp_item_error = function
  | ItemService.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | ItemService.Validation_error msg -> Printf.printf "validation error: %s\n" msg

let with_service init_svc f =
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = init_svc root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f root service)

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

module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module Todo = Kbases.Data.Todo

let make_blocking_rel ~source ~target =
  Relation.make ~source:(Todo.id source) ~target:(Todo.id target)
    ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true

let query_relations root =
  query_rows root
    {|SELECT s.niceid, r.kind, t.niceid, r.bidirectional
      FROM relation r
      JOIN (SELECT id, niceid FROM todo UNION ALL SELECT id, niceid FROM note) s
        ON s.id = r.source
      JOIN (SELECT id, niceid FROM todo UNION ALL SELECT id, niceid FROM note) t
        ON t.id = r.target
      ORDER BY s.niceid, r.kind|}
    []
