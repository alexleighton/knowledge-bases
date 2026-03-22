module Config = Repository.Config
module Jsonl = Repository.Jsonl
module Root = Repository.Root

type t = {
  root       : Root.t;
  jsonl_path : string;
}

type error = Sync_failed of string

let _sync_of_item_error = function
  | Item_service.Repository_error msg -> Sync_failed msg
  | Item_service.Validation_error msg -> Sync_failed msg

let _map_repo_error mapper e = _sync_of_item_error (mapper e)

let _map_config_error e = _map_repo_error Item_service.map_config_error e

let _map_jsonl_error = function
  | Jsonl.Io_error msg -> Sync_failed ("JSONL I/O error: " ^ msg)
  | Jsonl.Parse_error msg -> Sync_failed ("JSONL parse error: " ^ msg)

let init root ~jsonl_path = { root; jsonl_path }

let _config t = Root.config t.root

let _get_config t key =
  match Config.get (_config t) key with
  | Ok v -> Ok (Some v)
  | Error (Config.Not_found _) -> Ok None
  | Error (Config.Backend_failure msg) -> Error (Sync_failed msg)

let _set_config t key value =
  Config.set (_config t) key value
  |> Result.map_error _map_config_error

let _is_dirty t =
  match _get_config t "dirty" with
  | Ok (Some "true") -> Ok true
  | Ok _ -> Ok false
  | Error _ as e -> e

let _get_namespace t =
  Config.get (_config t) "namespace"
  |> Result.map_error _map_config_error

let mark_dirty t = _set_config t "dirty" "true"

let _hash_file path =
  try Ok (Digest.file path |> Digest.to_hex)
  with Sys_error msg -> Error (Sync_failed ("hash error: " ^ msg))

let flush t =
  let open Data.Result.Syntax in
  let* dirty = _is_dirty t in
  if not dirty then Ok ()
  else
    let* todos =
      Repository.Todo.list_all (Root.todo t.root)
      |> Result.map_error (_map_repo_error Item_service.map_todo_repo_error) in
    let* notes =
      Repository.Note.list_all (Root.note t.root)
      |> Result.map_error (_map_repo_error Item_service.map_note_repo_error) in
    let* relations =
      Repository.Relation.list_all (Root.relation t.root)
      |> Result.map_error (_map_repo_error Item_service.map_relation_repo_error) in
    let* namespace = _get_namespace t in
    let* () =
      Jsonl.write ~path:t.jsonl_path ~namespace ~todos ~notes ~relations
      |> Result.map_error _map_jsonl_error in
    let* file_hash = _hash_file t.jsonl_path in
    let* () = _set_config t "content_hash" file_hash in
    _set_config t "dirty" "false"

let force_rebuild t =
  let open Data.Result.Syntax in
  let* (_header, records) =
    Jsonl.read ~path:t.jsonl_path
    |> Result.map_error _map_jsonl_error in
  let sorted_records =
    List.sort (fun a b -> String.compare (Jsonl.record_sort_key a) (Jsonl.record_sort_key b)) records
  in
  let* () =
    Repository.Todo.delete_all (Root.todo t.root)
    |> Result.map_error (_map_repo_error Item_service.map_todo_repo_error) in
  let* () =
    Repository.Note.delete_all (Root.note t.root)
    |> Result.map_error (_map_repo_error Item_service.map_note_repo_error) in
  let* () =
    Repository.Relation.delete_all (Root.relation t.root)
    |> Result.map_error (_map_repo_error Item_service.map_relation_repo_error) in
  let* () =
    Repository.Niceid.delete_all (Root.niceid t.root)
    |> Result.map_error (_map_repo_error Item_service.map_niceid_repo_error) in
  let* () = Data.Result.sequence (List.map (fun record ->
    match record with
    | Jsonl.Todo { id; title; content; status; created_at; updated_at } ->
        Repository.Todo.import (Root.todo t.root) ~id ~title ~content ~status
          ~created_at ~updated_at ()
        |> Result.map (fun _ -> ())
        |> Result.map_error (_map_repo_error Item_service.map_todo_repo_error)
    | Jsonl.Note { id; title; content; status; created_at; updated_at } ->
        Repository.Note.import (Root.note t.root) ~id ~title ~content ~status
          ~created_at ~updated_at ()
        |> Result.map (fun _ -> ())
        |> Result.map_error (_map_repo_error Item_service.map_note_repo_error)
    | Jsonl.Relation rel ->
        Repository.Relation.create (Root.relation t.root) rel
        |> Result.map (fun _ -> ())
        |> Result.map_error (_map_repo_error Item_service.map_relation_repo_error)
  ) sorted_records) |> Result.map (fun _ -> ()) in
  let* file_hash = _hash_file t.jsonl_path in
  let* () = _set_config t "content_hash" file_hash in
  _set_config t "dirty" "false"

let rebuild_if_needed t =
  let open Data.Result.Syntax in
  if not (Sys.file_exists t.jsonl_path) then Ok ()
  else
    let* file_hash = _hash_file t.jsonl_path in
    let* stored_hash = _get_config t "content_hash" in
    match stored_hash with
    | None -> force_rebuild t
    | Some hash when not (String.equal hash file_hash) ->
        force_rebuild t
    | Some _ ->
        let* dirty = _is_dirty t in
        if dirty then flush t else Ok ()
