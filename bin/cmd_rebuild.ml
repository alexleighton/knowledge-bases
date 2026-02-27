module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service

let run () =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.force_rebuild (App_context.service ctx) with
    | Ok () -> print_endline "Rebuilt SQLite from .kbases.jsonl"
    | Error err -> Common.exit_with (Common.service_error_msg err))

let cmd_info = Cmd.info "rebuild" ~doc:"Rebuild SQLite from .kbases.jsonl."

let cmd =
  let term = Term.(const run $ const ()) in
  Cmd.v cmd_info term
