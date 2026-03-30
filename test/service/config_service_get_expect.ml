module Root = Kbases.Repository.Root
module Config = Kbases.Repository.Config
module ConfigService = Kbases.Service.Config_service

let pp_error = Test_helpers.pp_config_error
let with_config_service = Test_helpers.with_config_service

(* --- get tests --- *)

let%expect_test "get returns stored namespace" =
  with_config_service (fun root service ->
    ignore (Config.set (Root.config root) "namespace" "kb" : (unit, Config.error) result);
    match ConfigService.get service "namespace" with
    | Ok { key; value; _ } -> Printf.printf "%s=%s\n" key value
    | Error e -> pp_error e);
  [%expect {| namespace=kb |}]

let%expect_test "get returns default for gc_max_age when not set" =
  with_config_service (fun _root service ->
    match ConfigService.get service "gc_max_age" with
    | Ok { key; value; _ } -> Printf.printf "%s=%s\n" key value
    | Error e -> pp_error e);
  [%expect {| gc_max_age=2592000 |}]

let%expect_test "get returns default for mode when not set" =
  with_config_service (fun _root service ->
    match ConfigService.get service "mode" with
    | Ok { key; value; _ } -> Printf.printf "%s=%s\n" key value
    | Error e -> pp_error e);
  [%expect {| mode=shared |}]

let%expect_test "get returns stored gc_max_age" =
  with_config_service (fun root service ->
    ignore (Config.set (Root.config root) "gc_max_age" "604800" : (unit, Config.error) result);
    match ConfigService.get service "gc_max_age" with
    | Ok { key; value; _ } -> Printf.printf "%s=%s\n" key value
    | Error e -> pp_error e);
  [%expect {| gc_max_age=604800 |}]

let%expect_test "get returns Unknown_key for internal key dirty" =
  with_config_service (fun root service ->
    ignore (Config.set (Root.config root) "dirty" "true" : (unit, Config.error) result);
    match ConfigService.get service "dirty" with
    | Ok { key; value; _ } -> Printf.printf "%s=%s\n" key value
    | Error e -> pp_error e);
  [%expect {| unknown key: dirty |}]

let%expect_test "get returns Unknown_key for nonexistent key" =
  with_config_service (fun _root service ->
    match ConfigService.get service "nonexistent" with
    | Ok { key; value; _ } -> Printf.printf "%s=%s\n" key value
    | Error e -> pp_error e);
  [%expect {| unknown key: nonexistent |}]

(* --- list_user_facing tests --- *)

let%expect_test "list_user_facing returns all three keys with defaults" =
  with_config_service (fun root service ->
    ignore (Config.set (Root.config root) "namespace" "kb" : (unit, Config.error) result);
    match ConfigService.list_user_facing service with
    | Ok entries ->
        List.iter (fun (e : ConfigService.config_value) ->
          Printf.printf "%s=%s\n" e.key e.value) entries
    | Error e -> pp_error e);
  [%expect {|
    namespace=kb
    gc_max_age=2592000
    mode=shared
  |}]

let%expect_test "list_user_facing omits namespace when not set and no default" =
  with_config_service (fun _root service ->
    match ConfigService.list_user_facing service with
    | Ok entries ->
        Printf.printf "count=%d\n" (List.length entries);
        List.iter (fun (e : ConfigService.config_value) ->
          Printf.printf "%s=%s\n" e.key e.value) entries
    | Error e -> pp_error e);
  [%expect {|
    count=2
    gc_max_age=2592000
    mode=shared
  |}]
