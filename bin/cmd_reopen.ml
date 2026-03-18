module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Identifier = Kbases.Data.Identifier

let run identifier json =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.reopen (App_context.service ctx) ~identifier with
    | Ok (Service.Todo_item todo) ->
        let niceid = Identifier.to_string (Todo.niceid todo) in
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true; "action", `String "reopened";
            "type", `String "todo"; "niceid", `String niceid;
          ])
        else
          Printf.printf "Reopened todo: %s\n" niceid
    | Ok (Service.Note_item note) ->
        let niceid = Identifier.to_string (Note.niceid note) in
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true; "action", `String "reactivated";
            "type", `String "note"; "niceid", `String niceid;
          ])
        else
          Printf.printf "Reactivated note: %s\n" niceid
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

let identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the item to reopen." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Reopen a resolved todo:";
  `P "  bs reopen kb-0";
  `P "Reactivate an archived note:";
  `P "  bs reopen kb-1";
  `P "JSON output:";
  `P "  bs reopen kb-0 --json";
]

let cmd_info = Cmd.info "reopen"
  ~doc:"Return a terminal item to its initial status (Open/Active)."
  ~man:cmd_man

let cmd =
  let term = Term.(const run $ identifier_arg $ Common.json_flag) in
  Cmd.v cmd_info term
