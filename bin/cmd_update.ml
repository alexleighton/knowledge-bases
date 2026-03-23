module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier

let run identifier status title content_opt json =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let title =
      match title with
      | None -> None
      | Some t ->
          (try Some (Title.make t)
           with Invalid_argument msg -> Common.exit_with_error ~json msg)
    in
    let content =
      match Common.resolve_content_source content_opt with
      | None -> None
      | Some raw ->
          (try Some (Content.make raw)
           with Invalid_argument msg -> Common.exit_with_error ~json msg)
    in
    match Service.update (App_context.service ctx) ~identifier ?status ?title ?content () with
    | Ok (Service.Todo_item todo) ->
        let niceid = Identifier.to_string (Todo.niceid todo) in
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true; "action", `String "updated";
            "type", `String "todo"; "niceid", `String niceid;
          ])
        else
          Printf.printf "Updated todo: %s\n" niceid
    | Ok (Service.Note_item note) ->
        let niceid = Identifier.to_string (Note.niceid note) in
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true; "action", `String "updated";
            "type", `String "note"; "niceid", `String niceid;
          ])
        else
          Printf.printf "Updated note: %s\n" niceid
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

let identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the item to update." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let status_opt =
  let doc = "New status. Todos: open, in-progress, done. Notes: active, archived." in
  Arg.(value & opt (some string) None & info [ "status" ] ~docv:"STATUS" ~doc)

let title_opt =
  let doc = "New title." in
  Arg.(value & opt (some string) None & info [ "title" ] ~docv:"TITLE" ~doc)

let content_opt =
  let doc = "New content body. When absent and stdin is piped, content is read from stdin." in
  Arg.(value & opt (some string) None & info [ "content" ] ~docv:"CONTENT" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Change status:";
  `P "  bs update kb-0 --status in-progress";
  `P "Update title:";
  `P "  bs update kb-0 --title \"New title\"";
  `P "Set content inline:";
  `P "  bs update kb-0 --content \"New body\"";
  `P "Update content from stdin:";
  `P "  echo \"New body\" | bs update kb-0";
  `P "Machine-readable JSON output:";
  `P "  bs update kb-0 --title \"New title\" --json";
]

let cmd_info = Cmd.info "update" ~doc:"Update an existing item." ~man:cmd_man

let cmd =
  let term = Term.(const run $ identifier_arg $ status_opt $ title_opt $ content_opt $ Common.json_flag) in
  Cmd.v cmd_info term
