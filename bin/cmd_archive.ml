module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Identifier = Kbases.Data.Identifier

let run identifier json =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.archive (App_context.service ctx) ~identifier with
    | Ok note ->
        let niceid = Identifier.to_string (Note.niceid note) in
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true; "action", `String "archived";
            "type", `String "note"; "niceid", `String niceid;
          ])
        else
          Printf.printf "Archived note: %s\n" niceid
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

let identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the note to archive." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Mark a note as archived:";
  `P "  bs archive kb-1";
]

let cmd_info = Cmd.info "archive" ~doc:"Mark a note as archived." ~man:cmd_man

let cmd =
  let term = Term.(const run $ identifier_arg $ Common.json_flag) in
  Cmd.v cmd_info term
