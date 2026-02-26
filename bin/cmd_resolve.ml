module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Todo = Kbases.Data.Todo
module Identifier = Kbases.Data.Identifier

let run identifier =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.resolve (App_context.service ctx) ~identifier with
    | Ok todo ->
        Printf.printf "Resolved todo: %s\n" (Identifier.to_string (Todo.niceid todo))
    | Error err -> Common.exit_with (Common.service_error_msg err))

let identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the todo to resolve." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "bs resolve kb-0";
]

let cmd_info = Cmd.info "resolve" ~doc:"Mark a todo as done." ~man:cmd_man

let cmd =
  let term = Term.(const run $ identifier_arg) in
  Cmd.v cmd_info term
