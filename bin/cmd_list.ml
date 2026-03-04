module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Identifier = Kbases.Data.Identifier

let format_item = function
  | Service.Todo_item todo ->
      Printf.printf "%-6s  %-4s  %-12s  %s\n"
        (Identifier.to_string (Todo.niceid todo))
        "todo"
        (Todo.status_to_string (Todo.status todo))
        (Title.to_string (Todo.title todo))
  | Service.Note_item note ->
      Printf.printf "%-6s  %-4s  %-12s  %s\n"
        (Identifier.to_string (Note.niceid note))
        "note"
        (Note.status_to_string (Note.status note))
        (Title.to_string (Note.title note))

let item_to_json = function
  | Service.Todo_item todo ->
      `Assoc [
        "niceid", `String (Identifier.to_string (Todo.niceid todo));
        "type", `String "todo";
        "status", `String (Todo.status_to_string (Todo.status todo));
        "title", `String (Title.to_string (Todo.title todo));
      ]
  | Service.Note_item note ->
      `Assoc [
        "niceid", `String (Identifier.to_string (Note.niceid note));
        "type", `String "note";
        "status", `String (Note.status_to_string (Note.status note));
        "title", `String (Title.to_string (Note.title note));
      ]

let run entity_type statuses json =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.list (App_context.service ctx) ~entity_type ~statuses with
    | Ok items ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "items", `List (List.map item_to_json items);
          ])
        else
          List.iter format_item items
    | Error err -> Common.exit_with (Common.service_error_msg err))

let type_arg =
  let doc = "Optional entity type to list (todo|note)." in
  let types = Arg.enum [ "todo", "todo"; "note", "note" ] in
  Arg.(value & pos 0 (some types) None & info [] ~docv:"TYPE" ~doc)

let status_opt =
  let doc =
    "Filter by status. Repeatable. \
     Valid values: open, in-progress, done, active, archived."
  in
  let statuses = [
    "open", "open";
    "in-progress", "in-progress";
    "done", "done";
    "active", "active";
    "archived", "archived";
  ] in
  Arg.(value & opt_all (enum statuses) [] & info [ "status" ] ~docv:"STATUS" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "List all open todos and active notes:";
  `P "  bs list";
  `P "Filter by type and status:";
  `P "  bs list todo --status open";
  `P "Combine multiple status filters:";
  `P "  bs list --status open --status active";
]

let cmd_info = Cmd.info "list" ~doc:"List todos and notes in the knowledge base." ~man:cmd_man

let cmd =
  let term = Term.(const run $ type_arg $ status_opt $ Common.json_flag) in
  Cmd.v cmd_info term
