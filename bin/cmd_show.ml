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
module Timestamp = Kbases.Data.Timestamp

(* --- Output formatting --- *)

let format_item = function
  | Service.Todo_item todo ->
      Printf.printf "todo %s (%s)\nStatus: %s\nCreated: %s\nUpdated: %s\nTitle:  %s\n\n%s\n"
        (Identifier.to_string (Todo.niceid todo))
        (Typeid.to_string (Todo.id todo))
        (Todo.status_to_string (Todo.status todo))
        (Timestamp.to_display (Todo.created_at todo))
        (Timestamp.to_display (Todo.updated_at todo))
        (Title.to_string (Todo.title todo))
        (Content.to_string (Todo.content todo))
  | Service.Note_item note ->
      Printf.printf "note %s (%s)\nStatus: %s\nCreated: %s\nUpdated: %s\nTitle:  %s\n\n%s\n"
        (Identifier.to_string (Note.niceid note))
        (Typeid.to_string (Note.id note))
        (Note.status_to_string (Note.status note))
        (Timestamp.to_display (Note.created_at note))
        (Timestamp.to_display (Note.updated_at note))
        (Title.to_string (Note.title note))
        (Content.to_string (Note.content note))

let format_relation_entry (entry : Service.Query.relation_entry) =
  let open Service.Query in
  Printf.printf "  %s  %s  %s  %s%s\n"
    (Relation_kind.to_string entry.kind)
    (Identifier.to_string entry.niceid)
    entry.entity_type
    (Title.to_string entry.title)
    (match entry.blocking with Some true -> "  [blocking]" | _ -> "")

let format_relations ~outgoing ~incoming =
  if outgoing <> [] then begin
    Printf.printf "\nOutgoing:\n";
    List.iter format_relation_entry outgoing
  end;
  if incoming <> [] then begin
    Printf.printf "\nIncoming:\n";
    List.iter format_relation_entry incoming
  end

let format_show_result Service.Query.{ item; outgoing; incoming } =
  format_item item;
  format_relations ~outgoing ~incoming

let relation_entry_to_json (entry : Service.Query.relation_entry) =
  let open Service.Query in
  let base = [
    "kind", `String (Relation_kind.to_string entry.kind);
    "niceid", `String (Identifier.to_string entry.niceid);
    "type", `String entry.entity_type;
    "title", `String (Title.to_string entry.title);
  ] in
  let fields = match entry.blocking with
    | Some b -> base @ ["blocking", `Bool b]
    | None -> base
  in
  `Assoc fields

let item_to_json Service.Query.{ item; outgoing; incoming } =
  let item_fields = match item with
    | Service.Todo_item todo ->
        [
          "type", `String "todo";
          "niceid", `String (Identifier.to_string (Todo.niceid todo));
          "typeid", `String (Typeid.to_string (Todo.id todo));
          "status", `String (Todo.status_to_string (Todo.status todo));
          "title", `String (Title.to_string (Todo.title todo));
          "content", `String (Content.to_string (Todo.content todo));
          "created_at", `String (Timestamp.to_iso8601 (Todo.created_at todo));
          "updated_at", `String (Timestamp.to_iso8601 (Todo.updated_at todo));
        ]
    | Service.Note_item note ->
        [
          "type", `String "note";
          "niceid", `String (Identifier.to_string (Note.niceid note));
          "typeid", `String (Typeid.to_string (Note.id note));
          "status", `String (Note.status_to_string (Note.status note));
          "title", `String (Title.to_string (Note.title note));
          "content", `String (Content.to_string (Note.content note));
          "created_at", `String (Timestamp.to_iso8601 (Note.created_at note));
          "updated_at", `String (Timestamp.to_iso8601 (Note.updated_at note));
        ]
  in
  `Assoc (item_fields @ [
    "outgoing", `List (List.map relation_entry_to_json outgoing);
    "incoming", `List (List.map relation_entry_to_json incoming);
  ])

let run first_identifier rest_identifiers json =
  let identifiers = first_identifier :: rest_identifiers in
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.show_many (App_context.service ctx) ~identifiers with
    | Ok results ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "items", `List (List.map item_to_json results);
          ])
        else
          List.iteri (fun i result ->
            if i > 0 then print_string "---\n";
            format_show_result result
          ) results
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

(* --- CLI definitions --- *)

let first_identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId (e.g. todo_01abc...) of the item to show." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let rest_identifiers_arg =
  Arg.(value & pos_right 0 string [] & info [] ~docv:"IDENTIFIER")

let cmd_man = [
  `S "EXAMPLES";
  `P "Show a single item:";
  `P "  bs show kb-0";
  `P "Show multiple items at once:";
  `P "  bs show kb-0 kb-1 kb-2";
  `P "Show by TypeId:";
  `P "  bs show todo_01jmq...";
  `P "Machine-readable JSON output:";
  `P "  bs show kb-0 --json";
]

let cmd_info = Cmd.info "show" ~doc:"Display full details of one or more items." ~man:cmd_man

let cmd =
  let term = Term.(const run $ first_identifier_arg $ rest_identifiers_arg $ Common.json_flag) in
  Cmd.v cmd_info term
