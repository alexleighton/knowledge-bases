module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Identifier = Kbases.Data.Identifier

let result_to_json note =
  let niceid = Identifier.to_string (Note.niceid note) in
  `Assoc [
    "type", `String "note";
    "niceid", `String niceid;
  ]

let run first_identifier rest_identifiers json =
  let identifiers = first_identifier :: rest_identifiers in
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let result =
      Service.archive_many (App_context.service ctx) ~identifiers
    in
    match result with
    | Ok notes ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "archived", `List (List.map result_to_json notes);
          ])
        else
          List.iter (fun note ->
            Printf.printf "Archived note: %s\n"
              (Identifier.to_string (Note.niceid note))) notes
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

let first_identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the note to archive." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Mark a note as archived:";
  `P "  bs archive kb-1";
  `P "Archive multiple notes:";
  `P "  bs archive kb-1 kb-2 kb-3";
  `P "JSON output:";
  `P "  bs archive kb-1 --json";
]

let cmd_info = Cmd.info "archive" ~doc:"Mark a note as archived." ~man:cmd_man

let cmd =
  let term = Term.(const run $ first_identifier_arg $ Common.rest_identifiers_arg
                   $ Common.json_flag) in
  Cmd.v cmd_info term
