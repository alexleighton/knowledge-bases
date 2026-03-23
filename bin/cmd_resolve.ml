module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Todo = Kbases.Data.Todo
module Identifier = Kbases.Data.Identifier

let result_to_json todo =
  Common.item_summary_json ~entity_type:"todo" ~niceid:(Todo.niceid todo)

let run first_identifier rest_identifiers json =
  let identifiers = first_identifier :: rest_identifiers in
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let result =
      Service.resolve_many (App_context.service ctx) ~identifiers
    in
    match result with
    | Ok todos ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "resolved", `List (List.map result_to_json todos);
          ])
        else
          List.iter (fun todo ->
            Printf.printf "Resolved todo: %s\n"
              (Identifier.to_string (Todo.niceid todo))) todos
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

let first_identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the todo to resolve." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Mark a todo as done:";
  `P "  bs resolve kb-0";
  `P "Resolve multiple todos:";
  `P "  bs resolve kb-0 kb-1 kb-2";
  `P "JSON output:";
  `P "  bs resolve kb-0 --json";
]

let cmd_info = Cmd.info "resolve" ~doc:"Mark a todo as done." ~man:cmd_man

let cmd =
  let term = Term.(const run $ first_identifier_arg $ Common.rest_identifiers_arg
                   $ Common.json_flag) in
  Cmd.v cmd_info term
