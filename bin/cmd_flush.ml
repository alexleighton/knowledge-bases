module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service

let run json =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.flush (App_context.service ctx) with
    | Ok () ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true; "action", `String "flushed";
            "file", `String ".kbases.jsonl";
          ])
        else
          print_endline "Flushed to .kbases.jsonl"
    | Error err -> Common.exit_with (Common.service_error_msg err))

let cmd_man = [
  `S "EXAMPLES";
  `P "bs flush";
]

let cmd_info = Cmd.info "flush" ~doc:"Flush SQLite data to .kbases.jsonl." ~man:cmd_man

let cmd =
  let term = Term.(const run $ Common.json_flag) in
  Cmd.v cmd_info term
