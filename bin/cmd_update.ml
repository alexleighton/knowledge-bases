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
module Io = Kbases.Control.Io

let run identifier status title content_flag =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let title =
      match title with
      | None -> None
      | Some t ->
          (try Some (Title.make t)
           with Invalid_argument msg -> Common.exit_with msg)
    in
    let content =
      if content_flag then
        let raw = Io.read_all_stdin () in
        (try Some (Content.make raw)
         with Invalid_argument msg -> Common.exit_with msg)
      else None
    in
    match Service.update (App_context.service ctx) ~identifier ?status ?title ?content () with
    | Ok (Service.Todo_item todo) ->
        Printf.printf "Updated todo: %s\n" (Identifier.to_string (Todo.niceid todo))
    | Ok (Service.Note_item note) ->
        Printf.printf "Updated note: %s\n" (Identifier.to_string (Note.niceid note))
    | Error err -> Common.exit_with (Common.service_error_msg err))

let identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the item to update." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let status_opt =
  let doc = "New status (open, in-progress, done, active, archived)." in
  Arg.(value & opt (some string) None & info [ "status" ] ~docv:"STATUS" ~doc)

let title_opt =
  let doc = "New title." in
  Arg.(value & opt (some string) None & info [ "title" ] ~docv:"TITLE" ~doc)

let content_flag =
  let doc = "Read new content from stdin." in
  Arg.(value & flag & info [ "content" ] ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "bs update kb-0 --status in-progress";
  `P "bs update kb-0 --title \"New title\"";
  `P "echo \"New body\" | bs update kb-0 --content";
]

let cmd_info = Cmd.info "update" ~doc:"Update an existing item." ~man:cmd_man

let cmd =
  let term = Term.(const run $ identifier_arg $ status_opt $ title_opt $ content_flag) in
  Cmd.v cmd_info term
