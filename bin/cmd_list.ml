module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Identifier = Kbases.Data.Identifier
module Timestamp = Kbases.Data.Timestamp
module Query = Kbases.Service.Query_service

let format_item = function
  | Query.Todo_item todo ->
      Printf.printf "%-6s  %-4s  %-12s  %s\n"
        (Identifier.to_string (Todo.niceid todo))
        "todo"
        (Todo.status_to_string (Todo.status todo))
        (Title.to_string (Todo.title todo))
  | Query.Note_item note ->
      Printf.printf "%-6s  %-4s  %-12s  %s\n"
        (Identifier.to_string (Note.niceid note))
        "note"
        (Note.status_to_string (Note.status note))
        (Title.to_string (Note.title note))

let item_to_json = function
  | Query.Todo_item todo ->
      `Assoc [
        "niceid", `String (Identifier.to_string (Todo.niceid todo));
        "type", `String "todo";
        "status", `String (Todo.status_to_string (Todo.status todo));
        "title", `String (Title.to_string (Todo.title todo));
        "created_at", `String (Timestamp.to_iso8601 (Todo.created_at todo));
        "updated_at", `String (Timestamp.to_iso8601 (Todo.updated_at todo));
      ]
  | Query.Note_item note ->
      `Assoc [
        "niceid", `String (Identifier.to_string (Note.niceid note));
        "type", `String "note";
        "status", `String (Note.status_to_string (Note.status note));
        "title", `String (Title.to_string (Note.title note));
        "created_at", `String (Timestamp.to_iso8601 (Note.created_at note));
        "updated_at", `String (Timestamp.to_iso8601 (Note.updated_at note));
      ]

let format_counts todos notes =
  let plural label n = if n = 1 then label else label ^ "s" in
  let print_group label counts =
    List.iter (fun (status, count) ->
      Printf.printf "%d %s %s\n" count status (plural label count)
    ) counts
  in
  print_group "todo" todos;
  print_group "note" notes

let counts_to_json todos notes =
  let group_json counts =
    `Assoc (List.map (fun (status, count) -> status, `Int count) counts)
  in
  `Assoc [
    "ok", `Bool true;
    "counts", `Assoc [
      "todos", group_json todos;
      "notes", group_json notes;
    ];
  ]

let run entity_type statuses json available sort_str asc count
    depends_on related_to uni bi blocked transitive =
  let sort = match sort_str with
    | Some "created" -> Some Service.Sort_created
    | Some "updated" -> Some Service.Sort_updated
    | _ -> None
  in
  let relation_filters =
    Service.build_filters ~depends_on ~related_to ~uni ~bi
  in
  let spec = Service.{
    entity_type;
    statuses;
    available;
    sort;
    ascending = asc;
    count_only = count;
    relation_filters;
    transitive;
    blocked;
  } in
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.list (App_context.service ctx) spec with
    | Ok (Query.Items items) ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "items", `List (List.map item_to_json items);
          ])
        else
          List.iter format_item items
    | Ok (Query.Counts { todos; notes }) ->
        if json then Common.print_json (counts_to_json todos notes)
        else format_counts todos notes
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

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

let available_flag =
  let doc = "List only open, unblocked todos (available for claiming)." in
  Arg.(value & flag & info [ "available" ] ~doc)

let sort_opt =
  let doc = "Sort by created or updated timestamp (descending by default)." in
  let sorts = Arg.enum [ "created", "created"; "updated", "updated" ] in
  Arg.(value & opt (some sorts) None & info [ "sort" ] ~docv:"FIELD" ~doc)

let asc_flag =
  let doc = "Sort in ascending order (reverses default direction)." in
  Arg.(value & flag & info [ "asc" ] ~doc)

let count_flag =
  let doc = "Show counts grouped by type and status instead of listing items." in
  Arg.(value & flag & info [ "count" ] ~doc)

let blocked_flag =
  let doc = "Show only todos that are blocked by unresolved dependencies. \
             Cannot be combined with --available." in
  Arg.(value & flag & info [ "blocked" ] ~doc)

let transitive_flag =
  let doc = "Follow relations transitively (requires exactly one relation filter)." in
  Arg.(value & flag & info [ "transitive" ] ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "List all open todos and active notes:";
  `P "  bs list";
  `P "Filter by type and status:";
  `P "  bs list todo --status open";
  `P "List available (unblocked) todos:";
  `P "  bs list --available";
  `P "Sort by creation time:";
  `P "  bs list --sort created";
  `P "Sort ascending:";
  `P "  bs list --sort updated --asc";
  `P "Count items by status:";
  `P "  bs list --count";
  `P "Filter by relation:";
  `P "  bs list --depends-on kb-0";
  `P "Transitive relation filter:";
  `P "  bs list --depends-on kb-0 --transitive";
  `P "Show only blocked todos:";
  `P "  bs list --blocked";
  `P "Machine-readable JSON output:";
  `P "  bs list --json";
]

let cmd_info = Cmd.info "list" ~doc:"List todos and notes in the knowledge base." ~man:cmd_man

let cmd =
  let term = Term.(const run $ type_arg $ status_opt $ Common.json_flag
                   $ available_flag $ sort_opt $ asc_flag $ count_flag
                   $ Common.depends_on_opt $ Common.related_to_opt
                   $ Common.uni_opt $ Common.bi_opt $ blocked_flag
                   $ transitive_flag) in
  Cmd.v cmd_info term
