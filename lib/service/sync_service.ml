module Config = Repository.Config
module Jsonl = Repository.Jsonl
module Root = Repository.Root

type t = {
  root       : Root.t;
  jsonl_path : string;
}

type error = Sync_failed of string

let init root ~jsonl_path = { root; jsonl_path }

let _map_config_error = function
  | Config.Backend_failure msg -> Sync_failed msg
  | Config.Not_found key -> Sync_failed ("config key not found: " ^ key)

let _map_jsonl_error = function
  | Jsonl.Io_error msg -> Sync_failed ("JSONL I/O error: " ^ msg)
  | Jsonl.Parse_error msg -> Sync_failed ("JSONL parse error: " ^ msg)

let _config t = Root.config t.root

let _get_config t key =
  match Config.get (_config t) key with
  | Ok v -> Ok (Some v)
  | Error (Config.Not_found _) -> Ok None
  | Error (Config.Backend_failure msg) -> Error (Sync_failed msg)

let _set_config t key value =
  Config.set (_config t) key value
  |> Result.map_error _map_config_error

let mark_dirty t = _set_config t "dirty" "true"

let _is_dirty t =
  match _get_config t "dirty" with
  | Ok (Some "true") -> Ok true
  | Ok _ -> Ok false
  | Error _ as e -> e

let _get_namespace t =
  Config.get (_config t) "namespace"
  |> Result.map_error _map_config_error

let _map_todo_error = function
  | Repository.Todo.Backend_failure msg -> Sync_failed msg
  | Repository.Todo.Not_found _ -> Sync_failed "todo not found"
  | Repository.Todo.Duplicate_niceid _ -> Sync_failed "duplicate niceid"

let _map_note_error = function
  | Repository.Note.Backend_failure msg -> Sync_failed msg
  | Repository.Note.Not_found _ -> Sync_failed "note not found"
  | Repository.Note.Duplicate_niceid _ -> Sync_failed "duplicate niceid"

let _map_relation_error = function
  | Repository.Relation.Backend_failure msg -> Sync_failed msg
  | Repository.Relation.Duplicate -> Sync_failed "duplicate relation"

let _map_niceid_error = function
  | Repository.Niceid.Backend_failure msg -> Sync_failed msg

let flush t =
  let open Data.Result.Syntax in
  let* dirty = _is_dirty t in
  if not dirty then Ok ()
  else
    let* todos =
      Repository.Todo.list_all (Root.todo t.root)
      |> Result.map_error _map_todo_error in
    let* notes =
      Repository.Note.list_all (Root.note t.root)
      |> Result.map_error _map_note_error in
    let* relations =
      Repository.Relation.list_all (Root.relation t.root)
      |> Result.map_error _map_relation_error in
    let* namespace = _get_namespace t in
    let* content_hash =
      Jsonl.write ~path:t.jsonl_path ~namespace ~todos ~notes ~relations
      |> Result.map_error _map_jsonl_error in
    let* () = _set_config t "content_hash" content_hash in
    _set_config t "dirty" "false"

let _record_sort_key = function
  | Jsonl.Todo { id; _ } -> Data.Uuid.Typeid.to_string id
  | Jsonl.Note { id; _ } -> Data.Uuid.Typeid.to_string id
  | Jsonl.Relation rel ->
      "relation:" ^
      Data.Uuid.Typeid.to_string (Data.Relation.source rel) ^ ":" ^
      Data.Uuid.Typeid.to_string (Data.Relation.target rel) ^ ":" ^
      Data.Relation_kind.to_string (Data.Relation.kind rel)

let force_rebuild t =
  let open Data.Result.Syntax in
  let* (header, records) =
    Jsonl.read ~path:t.jsonl_path
    |> Result.map_error _map_jsonl_error in
  let sorted_records =
    List.sort (fun a b -> String.compare (_record_sort_key a) (_record_sort_key b)) records
  in
  let* () =
    Repository.Todo.delete_all (Root.todo t.root)
    |> Result.map_error _map_todo_error in
  let* () =
    Repository.Note.delete_all (Root.note t.root)
    |> Result.map_error _map_note_error in
  let* () =
    Repository.Relation.delete_all (Root.relation t.root)
    |> Result.map_error _map_relation_error in
  let* () =
    Repository.Niceid.delete_all (Root.niceid t.root)
    |> Result.map_error _map_niceid_error in
  let* () = Data.Result.sequence (List.map (fun record ->
    match record with
    | Jsonl.Todo { id; title; content; status } ->
        Repository.Todo.import (Root.todo t.root) ~id ~title ~content ~status ()
        |> Result.map (fun _ -> ())
        |> Result.map_error _map_todo_error
    | Jsonl.Note { id; title; content; status } ->
        Repository.Note.import (Root.note t.root) ~id ~title ~content ~status ()
        |> Result.map (fun _ -> ())
        |> Result.map_error _map_note_error
    | Jsonl.Relation rel ->
        Repository.Relation.create (Root.relation t.root) rel
        |> Result.map (fun _ -> ())
        |> Result.map_error _map_relation_error
  ) sorted_records) |> Result.map (fun _ -> ()) in
  let* () = _set_config t "content_hash" header.Jsonl.content_hash in
  _set_config t "dirty" "false"

let rebuild_if_needed t =
  let open Data.Result.Syntax in
  if not (Sys.file_exists t.jsonl_path) then Ok ()
  else
    let* header =
      Jsonl.read_header ~path:t.jsonl_path
      |> Result.map_error _map_jsonl_error in
    let* stored_hash = _get_config t "content_hash" in
    match stored_hash with
    | None -> force_rebuild t
    | Some hash when not (String.equal hash header.Jsonl.content_hash) ->
        force_rebuild t
    | Some _ ->
        let* dirty = _is_dirty t in
        if dirty then flush t else Ok ()
