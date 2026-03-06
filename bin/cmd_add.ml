module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid

let resolve_content ~json content_opt =
  match Common.resolve_content_source content_opt with
  | Some content -> content
  | None -> Common.exit_with_error ~json "No content provided. Use --content or pipe content to stdin."

let run_add ~entity_type ~add_simple ~add_with_relations
    title content_opt depends_on related_to uni bi blocking json =
  let specs = Service.build_specs ~depends_on ~related_to ~uni ~bi ~blocking in
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let content = resolve_content ~json content_opt in
    let title   = try Title.make   title   with Invalid_argument msg -> Common.exit_with_error ~json msg in
    let content = try Content.make content with Invalid_argument msg -> Common.exit_with_error ~json msg in
    let service = App_context.service ctx in
    match specs with
    | [] ->
        (match add_simple service ~title ~content with
        | Ok (niceid, typeid) ->
            if json then
              Common.print_json (`Assoc [
                "ok", `Bool true;
                "type", `String entity_type;
                "niceid", `String niceid;
                "typeid", `String typeid;
              ])
            else
              Printf.printf "Created %s: %s (%s)\n" entity_type niceid typeid
        | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))
    | specs ->
        (match add_with_relations service ~title ~content ~specs with
        | Ok { Service.niceid; typeid; relations; _ } ->
            let niceid = Identifier.to_string niceid in
            let typeid = Typeid.to_string typeid in
            if json then
              Common.print_json (`Assoc [
                "ok", `Bool true;
                "type", `String entity_type;
                "niceid", `String niceid;
                "typeid", `String typeid;
                "relations", `List (List.map Cmd_show.relation_entry_to_json relations);
              ])
            else begin
              Printf.printf "Created %s: %s (%s)\n" entity_type niceid typeid;
              List.iter Cmd_show.format_relation_entry relations
            end
        | Error err -> Common.exit_with_error ~json (Common.service_error_msg err)))

let add_note_simple svc ~title ~content =
  Service.add_note svc ~title ~content
  |> Result.map (fun note ->
    Identifier.to_string (Note.niceid note),
    Typeid.to_string (Note.id note))

let add_note_with_rels svc ~title ~content ~specs =
  Service.add_note_with_relations svc ~title ~content ~specs

let add_todo_simple svc ~title ~content =
  Service.add_todo svc ~title ~content ()
  |> Result.map (fun todo ->
    Identifier.to_string (Todo.niceid todo),
    Typeid.to_string (Todo.id todo))

let add_todo_with_rels svc ~title ~content ~specs =
  Service.add_todo_with_relations svc ~title ~content ~specs ()

let run_note = run_add ~entity_type:"note"
  ~add_simple:add_note_simple ~add_with_relations:add_note_with_rels

let run_todo = run_add ~entity_type:"todo"
  ~add_simple:add_todo_simple ~add_with_relations:add_todo_with_rels

(* --- CLI definitions --- *)

let title_arg =
  let doc = "Title of the resource to create." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"TITLE" ~doc)

let content_opt =
  let doc = "Content body. When absent, content is read from stdin." in
  Arg.(value & opt (some string) None & info ["content"] ~docv:"CONTENT" ~doc)

let add_doc = "Commands that create resources in the knowledge base."

let add_man = [
  `S "EXAMPLES";
  `P "Create a note from stdin:";
  `P "  echo \"Meeting notes\" | bs add note \"Standup\"";
  `P "Create a todo with inline content:";
  `P "  bs add todo \"Fix CI\" --content \"Investigate flaky test\"";
]

let add_info = Cmd.info "add" ~doc:add_doc ~man:add_man

let note_doc = "Create a new note in the knowledge base."

let note_man = [
  `S "EXAMPLES";
  `P "Create from stdin:";
  `P "  echo \"Body text\" | bs add note \"Title\"";
  `P "Create with inline content:";
  `P "  bs add note \"Title\" --content \"Body text\"";
  `P "Create with a dependency:";
  `P "  bs add note \"Title\" --content \"Body\" --depends-on kb-0";
  `P "Create with a custom unidirectional relation:";
  `P "  bs add note \"Title\" --content \"Body\" --uni designed-by,kb-0";
]

let note_info = Cmd.info "note" ~doc:note_doc ~man:note_man

let note_cmd =
  let term = Term.(const run_note $ title_arg $ content_opt $ Common.depends_on_opt $ Common.related_to_opt $ Common.uni_opt $ Common.bi_opt $ Common.blocking_flag $ Common.json_flag) in
  Cmd.v note_info term

let todo_doc = "Create a new todo in the knowledge base."

let todo_man = [
  `S "EXAMPLES";
  `P "Create from stdin:";
  `P "  echo \"Content\" | bs add todo \"Title\"";
  `P "Create with inline content:";
  `P "  bs add todo \"Title\" --content \"Content\"";
  `P "Create with a dependency:";
  `P "  bs add todo \"Title\" --content \"Content\" --depends-on kb-0";
  `P "Create with a custom unidirectional relation:";
  `P "  bs add todo \"Title\" --content \"Content\" --uni blocks,kb-1";
]

let todo_info = Cmd.info "todo" ~doc:todo_doc ~man:todo_man

let todo_cmd =
  let term = Term.(const run_todo $ title_arg $ content_opt $ Common.depends_on_opt $ Common.related_to_opt $ Common.uni_opt $ Common.bi_opt $ Common.blocking_flag $ Common.json_flag) in
  Cmd.v todo_info term

let cmd = Cmd.group add_info [note_cmd; todo_cmd]
