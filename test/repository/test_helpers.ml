module Root = Kbases.Repository.Root
module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo
module Niceid = Kbases.Repository.Niceid
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid

let with_root f =
  match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
  | Ok root ->
      Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f root)
  | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)

let with_db f =
  let db = Sqlite3.db_open ":memory:" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () -> f db)

let unwrap_note = function
  | Ok v -> v
  | Error (NoteRepo.Not_found (`Id id)) ->
      failwith ("not found by id: " ^ Typeid.to_string id)
  | Error (NoteRepo.Not_found (`Niceid niceid)) ->
      failwith ("not found by niceid: " ^ Identifier.to_string niceid)
  | Error (NoteRepo.Duplicate_niceid niceid) ->
      failwith ("duplicate niceid: " ^ Identifier.to_string niceid)
  | Error (NoteRepo.Backend_failure msg) ->
      failwith ("backend failure: " ^ msg)

let unwrap_todo = function
  | Ok v -> v
  | Error (TodoRepo.Not_found (`Id id)) ->
      failwith ("not found by id: " ^ Typeid.to_string id)
  | Error (TodoRepo.Not_found (`Niceid niceid)) ->
      failwith ("not found by niceid: " ^ Identifier.to_string niceid)
  | Error (TodoRepo.Duplicate_niceid niceid) ->
      failwith ("duplicate niceid: " ^ Identifier.to_string niceid)
  | Error (TodoRepo.Backend_failure msg) ->
      failwith ("backend failure: " ^ msg)

let unwrap_niceid = function
  | Ok v -> v
  | Error (Niceid.Backend_failure msg) -> failwith ("backend failure: " ^ msg)
  | Error Niceid.Not_found -> failwith "niceid not found"

let query_db_raw = Test_common.query_db_raw
let query_rows_raw = Test_common.query_rows_raw
let query_count_raw = Test_common.query_count_raw
let query_db = Test_common.query_db
let query_rows = Test_common.query_rows
let query_count = Test_common.query_count
