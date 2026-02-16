module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid
module Io = Kbases.Control.Io

let add_doc = "Commands that create resources in the knowledge base."

let add_info = Cmd.info "add" ~doc:add_doc

let note_doc = "Create a new note in the knowledge base."

let note_info = Cmd.info "note" ~doc:note_doc

let exit_with msg =
  prerr_endline ("Error: " ^ msg);
  exit 1

let run_note db_override title =
  let db_file = Common.resolve_db_file ~override:db_override in
  let ctx = App_context.init ~db_file ~namespace:None in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let content = Io.read_all_stdin () in
    match Service.add_note (App_context.service ctx) ~title ~content with
    | Ok note ->
        let niceid = Identifier.to_string (Note.niceid note) in
        let typeid = Typeid.to_string (Note.id note) in
        Printf.printf "Created note: %s (%s)\n" niceid typeid
    | Error err ->
        let msg =
          match err with
          | Service.Repository_error text -> text
          | Service.Validation_error text -> text
        in
        exit_with msg)

let title_arg =
  let doc = "Title of the note to create." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"TITLE" ~doc)

let note_cmd =
  let term =
    Term.(const run_note $ Common.db_file_arg $ title_arg)
  in
  Cmd.v note_info term

let cmd = Cmd.group add_info [note_cmd]
