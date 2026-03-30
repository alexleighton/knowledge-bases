(** Configuration service implementation. *)

module Config = Repository.Config
module Root = Repository.Root
module Namespace = Data.Namespace

type config_value = { key : string; value : string; is_default : bool }

type error =
  | Unknown_key of string
  | Validation_error of string
  | Nothing_to_update
  | Backend_error of string

type entry = {
  entry_key   : string;
  user_facing : bool;
  default     : string option;
  validate    : string -> (unit, string) result;
  on_set      : t -> old_value:string -> new_value:string -> (unit, error) result;
}

and t = {
  config  : Config.t;
  root    : Root.t;
  dir     : string;
  entries : entry list;
} [@@warning "-69"]

(* --- Error mapping --- *)

let _map_config_error = function
  | Config.Backend_failure msg -> Backend_error msg
  | Config.Not_found k -> Backend_error ("config key not found: " ^ k)

let _map_sync_error (Sync_service.Sync_failed msg) = Backend_error msg

let _map_niceid_error = function
  | Repository.Niceid.Backend_failure msg -> Backend_error msg
  | Repository.Niceid.Not_found -> Backend_error "niceid not found"

let _map_todo_repo_error = function
  | Repository.Todo.Backend_failure msg -> Backend_error msg
  | Repository.Todo.Not_found _ -> Backend_error "entity not found"
  | Repository.Todo.Duplicate_niceid _ -> Backend_error "duplicate niceid"

let _map_note_repo_error = function
  | Repository.Note.Backend_failure msg -> Backend_error msg
  | Repository.Note.Not_found _ -> Backend_error "entity not found"
  | Repository.Note.Duplicate_niceid _ -> Backend_error "duplicate niceid"

(* --- Validators --- *)

let _validate_namespace s =
  Namespace.validate s
  |> Result.map (fun _ -> ())

let _validate_gc_max_age s =
  match int_of_string_opt s with
  | Some n when n >= 0 -> Ok ()
  | Some _ -> Error "gc_max_age must be a non-negative integer (seconds)"
  | None -> Error (Printf.sprintf "invalid gc_max_age: %S (expected integer seconds)" s)

let _validate_mode s =
  if s = "local" || s = "shared" then Ok ()
  else Error (Printf.sprintf "invalid mode: %S (expected \"local\" or \"shared\")" s)

(* --- Internal helpers --- *)

let _find_entry t key =
  List.find_opt (fun e -> e.entry_key = key && e.user_facing) t.entries

let _get_current t entry =
  match Config.get t.config entry.entry_key with
  | Ok v -> Ok (Some v, false)
  | Error (Config.Not_found _) -> (
      match entry.default with
      | Some d -> Ok (Some d, true)
      | None -> Ok (None, true))
  | Error (Config.Backend_failure _ as e) -> Error (_map_config_error e)

(* --- Side-effect helpers --- *)

let _rename_namespace t ~old_ns ~new_ns =
  let db = Root.db t.root in
  let old_prefix = old_ns ^ "-" in
  let new_prefix = new_ns ^ "-" in
  Repository.Sqlite.with_savepoint db ~name:"rename_ns"
    ~on_begin_error:(fun msg -> Backend_error msg)
    (fun () ->
      let open Result.Syntax in
      let* () =
        Repository.Niceid.rename_namespace (Root.niceid t.root)
          ~old_ns ~new_ns
        |> Result.map_error _map_niceid_error
      in
      let* () =
        Repository.Todo.rename_namespace (Root.todo t.root)
          ~old_prefix ~new_prefix
        |> Result.map_error _map_todo_repo_error
      in
      Repository.Note.rename_namespace (Root.note t.root)
        ~old_prefix ~new_prefix
      |> Result.map_error _map_note_repo_error)

let _flush_if_shared t ~mode =
  if mode <> "shared" then Ok ()
  else
    let jsonl_path = Filename.concat t.dir Data.Kb_filenames.jsonl in
    let sync = Sync_service.init t.root ~jsonl_path in
    let open Result.Syntax in
    let* () =
      Sync_service.rebuild_if_needed sync
      |> Result.map_error _map_sync_error
    in
    let* () =
      Sync_service.mark_dirty sync
      |> Result.map_error _map_sync_error
    in
    Sync_service.flush sync |> Result.map_error _map_sync_error

(* --- on_set callbacks --- *)

let _on_set_noop _t ~old_value:_ ~new_value:_ = Ok ()

let _on_set_namespace t ~old_value ~new_value =
  let open Result.Syntax in
  let* () = _rename_namespace t ~old_ns:old_value ~new_ns:new_value in
  let mode = match Config.get t.config "mode" with
    | Ok m -> m | Error _ -> "shared" in
  _flush_if_shared t ~mode

let _on_set_mode t ~old_value:_ ~new_value =
  _flush_if_shared t ~mode:new_value

(* --- Defaults --- *)

let default_gc_max_age = "2592000"

(* --- Registry --- *)

let _registry = [
  { entry_key = "namespace"; user_facing = true; default = None;
    validate = _validate_namespace; on_set = _on_set_namespace };
  { entry_key = "gc_max_age"; user_facing = true; default = Some default_gc_max_age;
    validate = _validate_gc_max_age; on_set = _on_set_noop };
  { entry_key = "mode"; user_facing = true; default = Some "shared";
    validate = _validate_mode; on_set = _on_set_mode };
]

(* --- Initialization --- *)

let init root ~dir =
  { config = Root.config root; root; dir; entries = _registry }

(* --- Public operations --- *)

let get t key =
  match _find_entry t key with
  | None -> Error (Unknown_key key)
  | Some entry ->
      match _get_current t entry with
      | Ok (Some value, is_default) -> Ok { key; value; is_default }
      | Ok (None, _) ->
          Error (Backend_error
            ("config key has no value and no default: " ^ key))
      | Error e -> Error e

let set ?(run_on_set = true) t key value =
  let open Result.Syntax in
  let* entry = match _find_entry t key with
    | Some e -> Ok e | None -> Error (Unknown_key key) in
  let* () = entry.validate value
    |> Result.map_error (fun msg -> Validation_error msg) in
  let* (old_value, _) = _get_current t entry in
  if old_value = Some value then Error Nothing_to_update
  else
    let db = Root.db t.root in
    Repository.Sqlite.with_transaction db
      ~on_begin_error:(fun msg -> Backend_error msg)
      (fun () ->
        let* () = Config.set t.config key value
          |> Result.map_error _map_config_error in
        if run_on_set then
          let old = match old_value with Some v -> v | None -> value in
          entry.on_set t ~old_value:old ~new_value:value
        else
          Ok ())

let list_user_facing t =
  let user_entries = List.filter (fun e -> e.user_facing) t.entries in
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | entry :: rest ->
        match _get_current t entry with
        | Ok (Some value, is_default) ->
            collect ({ key = entry.entry_key; value; is_default } :: acc) rest
        | Ok (None, _) -> collect acc rest
        | Error e -> Error e
  in
  collect [] user_entries
