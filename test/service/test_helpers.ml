module Root = Kbases.Repository.Root
module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo
module Identifier = Kbases.Data.Identifier
module ItemService = Kbases.Service.Item_service

let with_git_root = Test_common.with_git_root
let with_temp_dir = Test_common.with_temp_dir

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

let query_db = Test_common.query_db
let query_rows = Test_common.query_rows
let query_count = Test_common.query_count

module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module Todo = Kbases.Data.Todo

let make_blocking_rel ~source ~target =
  Relation.make ~source:(Todo.id source) ~target:(Todo.id target)
    ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true

let query_relations root =
  Test_common.query_rows root
    {|SELECT s.niceid, r.kind, t.niceid, r.bidirectional
      FROM relation r
      JOIN (SELECT id, niceid FROM todo UNION ALL SELECT id, niceid FROM note) s
        ON s.id = r.source
      JOIN (SELECT id, niceid FROM todo UNION ALL SELECT id, niceid FROM note) t
        ON t.id = r.target
      ORDER BY s.niceid, r.kind|}
    []

(* -- Query-service helpers (shared across query_service_*_expect.ml splits) -- *)

module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module QueryService = Kbases.Service.Query_service

let print_query_items items =
  List.iter (function
    | QueryService.Todo_item todo ->
        Printf.printf "%s todo %s %s\n"
          (Identifier.to_string (Todo.niceid todo))
          (Todo.status_to_string (Todo.status todo))
          (Title.to_string (Todo.title todo))
    | QueryService.Note_item note ->
        Printf.printf "%s note %s %s\n"
          (Identifier.to_string (Note.niceid note))
          (Note.status_to_string (Note.status note))
          (Title.to_string (Note.title note)))
    items

let unwrap_query_items result =
  match result with
  | Ok (QueryService.Items v) -> v
  | Ok (QueryService.Counts _) -> failwith "unexpected counts"
  | Error err -> pp_item_error err; failwith "unexpected error"

(* -- Lifecycle helpers (shared across lifecycle_*_expect.ml splits) -- *)

module Lifecycle = Kbases.Service.Lifecycle

let pp_lifecycle_error = function
  | Lifecycle.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | Lifecycle.Validation_error msg -> Printf.printf "validation error: %s\n" msg

let expect_lifecycle_ok result f =
  match result with
  | Error err -> pp_lifecycle_error err
  | Ok v -> f v

(* -- Config_service helpers (shared across config_service_*_expect.ml splits) -- *)

module ConfigService = Kbases.Service.Config_service

let dir_without_kbases_jsonl = "/tmp/test"

let pp_config_error = function
  | ConfigService.Unknown_key k -> Printf.printf "unknown key: %s\n" k
  | ConfigService.Validation_error msg -> Printf.printf "validation error: %s\n" msg
  | ConfigService.Nothing_to_update -> Printf.printf "nothing to update\n"
  | ConfigService.Backend_error msg -> Printf.printf "backend error: %s\n" msg

let with_config_service f =
  with_service
    (fun root -> ConfigService.init root ~dir:dir_without_kbases_jsonl)
    f

(* -- Kb_service helpers (shared across kb_service_*_expect.ml splits) -- *)

module Service = Kbases.Service.Kb_service

let expect_service_ok result f =
  match result with
  | Error err -> pp_item_error err
  | Ok v -> f v

let with_open_kb f =
  expect_service_ok (Service.open_kb ()) (fun (root, service) ->
    Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f root service))
