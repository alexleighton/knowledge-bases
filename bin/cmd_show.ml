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
module Typeid = Kbases.Data.Uuid.Typeid
module Relation_kind = Kbases.Data.Relation_kind

let format_item = function
  | Service.Todo_item todo ->
      Printf.printf "todo %s (%s)\nStatus: %s\nTitle:  %s\n\n%s\n"
        (Identifier.to_string (Todo.niceid todo))
        (Typeid.to_string (Todo.id todo))
        (Todo.status_to_string (Todo.status todo))
        (Title.to_string (Todo.title todo))
        (Content.to_string (Todo.content todo))
  | Service.Note_item note ->
      Printf.printf "note %s (%s)\nStatus: %s\nTitle:  %s\n\n%s\n"
        (Identifier.to_string (Note.niceid note))
        (Typeid.to_string (Note.id note))
        (Note.status_to_string (Note.status note))
        (Title.to_string (Note.title note))
        (Content.to_string (Note.content note))

let format_relation_entry (entry : Service.relation_entry) =
  Printf.printf "  %s  %s  %s  %s\n"
    (Relation_kind.to_string entry.Service.kind)
    (Identifier.to_string entry.Service.niceid)
    entry.Service.entity_type
    (Title.to_string entry.Service.title)

let format_relations ~outgoing ~incoming =
  if outgoing <> [] then begin
    Printf.printf "\nOutgoing:\n";
    List.iter format_relation_entry outgoing
  end;
  if incoming <> [] then begin
    Printf.printf "\nIncoming:\n";
    List.iter format_relation_entry incoming
  end

let run identifier =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.show (App_context.service ctx) ~identifier with
    | Ok Service.{ item; outgoing; incoming } ->
        format_item item;
        format_relations ~outgoing ~incoming
    | Error err -> Common.exit_with (Common.service_error_msg err))

let identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId (e.g. todo_01abc...) of the item to show." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "bs show kb-0";
  `P "bs show todo_01jmq...";
]

let cmd_info = Cmd.info "show" ~doc:"Display full details of an item." ~man:cmd_man

let cmd =
  let term = Term.(const run $ identifier_arg) in
  Cmd.v cmd_info term
