module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module ConfigService = Kbases.Service.Config_service

let error_msg = function
  | ConfigService.Unknown_key k ->
      Printf.sprintf "unknown config key: %s" k
  | ConfigService.Validation_error msg -> msg
  | ConfigService.Nothing_to_update -> "nothing to update"
  | ConfigService.Backend_error msg -> msg

let with_config_service f =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    f (App_context.config_svc ctx))

(* --- get subcommand --- *)

let run_get json key =
  with_config_service (fun service ->
    match ConfigService.get service key with
    | Ok { ConfigService.key = k; value; _ } ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true; "key", `String k; "value", `String value ])
        else
          print_endline value
    | Error e -> Common.exit_with_error ~json (error_msg e))

let get_key_arg =
  Arg.(required & pos 0 (some string) None & info [] ~docv:"KEY"
    ~doc:"The configuration key to retrieve.")

let get_man = [
  `S "EXAMPLES";
  `P "Show the current namespace:";
  `P "  bs config get namespace";
  `P "Show the GC max age setting:";
  `P "  bs config get gc_max_age";
  `P "Machine-readable JSON output:";
  `P "  bs config get gc_max_age --json";
]

let get_info = Cmd.info "get"
  ~doc:"Get a configuration value."
  ~man:get_man

let get_cmd =
  let term = Term.(const run_get $ Common.json_flag $ get_key_arg) in
  Cmd.v get_info term

(* --- set subcommand --- *)

let run_set json key value =
  with_config_service (fun service ->
    match ConfigService.set service key value with
    | Ok () ->
        if json then
          Common.print_json (`Assoc [ "ok", `Bool true ])
        else
          Printf.printf "%s set to: %s\n" key value
    | Error e -> Common.exit_with_error ~json (error_msg e))

let set_key_arg =
  Arg.(required & pos 0 (some string) None & info [] ~docv:"KEY"
    ~doc:"The configuration key to set.")

let set_value_arg =
  Arg.(required & pos 1 (some string) None & info [] ~docv:"VALUE"
    ~doc:"The new value for the configuration key.")

let set_man = [
  `S "EXAMPLES";
  `P "Change the GC max age to 7 days (in seconds):";
  `P "  bs config set gc_max_age 604800";
  `P "Rename the namespace:";
  `P "  bs config set namespace proj";
  `P "Switch to local mode (SQLite only, no JSONL sync):";
  `P "  bs config set mode local";
  `P "Machine-readable JSON output:";
  `P "  bs config set gc_max_age 604800 --json";
]

let set_info = Cmd.info "set"
  ~doc:"Set a configuration value."
  ~man:set_man

let set_cmd =
  let term = Term.(const run_set $ Common.json_flag $ set_key_arg
                   $ set_value_arg) in
  Cmd.v set_info term

(* --- list subcommand --- *)

let run_list json =
  with_config_service (fun service ->
    match ConfigService.list_user_facing service with
    | Ok entries ->
        if json then
          let items = List.map (fun (e : ConfigService.config_value) ->
            `Assoc [ "key", `String e.ConfigService.key;
                     "value", `String e.ConfigService.value ]
          ) entries in
          Common.print_json (`Assoc [
            "ok", `Bool true; "entries", `List items ])
        else
          List.iter (fun (e : ConfigService.config_value) ->
            Printf.printf "%-12s  %s\n" e.ConfigService.key
              e.ConfigService.value) entries
    | Error e -> Common.exit_with_error ~json (error_msg e))

let list_man = [
  `S "EXAMPLES";
  `P "Show all configuration values:";
  `P "  bs config list";
  `P "Machine-readable JSON output:";
  `P "  bs config list --json";
]

let list_info = Cmd.info "list"
  ~doc:"List all configuration values."
  ~man:list_man

let list_cmd =
  let term = Term.(const run_list $ Common.json_flag) in
  Cmd.v list_info term

(* --- config group --- *)

let cmd_man = [
  `S "DESCRIPTION";
  `P "Inspect and modify knowledge-base configuration. User-facing keys \
      are $(b,namespace), $(b,gc_max_age), and $(b,mode).";
  `S "EXAMPLES";
  `P "List all settings:";
  `P "  bs config list";
  `P "Get a single setting:";
  `P "  bs config get namespace";
  `P "Change a setting:";
  `P "  bs config set gc_max_age 604800";
]

let cmd_info = Cmd.info "config"
  ~doc:"Inspect and modify knowledge-base configuration."
  ~man:cmd_man

let cmd = Cmd.group cmd_info [ get_cmd; set_cmd; list_cmd ]
