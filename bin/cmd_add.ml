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
module Io = Kbases.Control.Io

let add_doc = "Commands that create resources in the knowledge base."

let add_man = [
  `S "EXAMPLES";
  `P "Create a note from stdin:";
  `P "  echo \"Meeting notes\" | bs add note \"Standup\"";
  `P "Create a todo from stdin:";
  `P "  echo \"Investigate flaky test\" | bs add todo \"Fix CI\"";
]

let add_info = Cmd.info "add" ~doc:add_doc ~man:add_man

let note_doc = "Create a new note in the knowledge base."

let note_man = [
  `S "EXAMPLES";
  `P "echo \"Body text\" | bs add note \"Title\"";
]

let note_info = Cmd.info "note" ~doc:note_doc ~man:note_man

let todo_doc = "Create a new todo in the knowledge base."

let todo_man = [
  `S "EXAMPLES";
  `P "echo \"Content\" | bs add todo \"Title\"";
]

let todo_info = Cmd.info "todo" ~doc:todo_doc ~man:todo_man

let service_error_msg = function
  | Service.Repository_error text | Service.Validation_error text -> text

let run_note db_override title =
  let db_file = Common.resolve_db_file ~override:db_override in
  let ctx = App_context.init ~db_file ~namespace:None in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let content = Io.read_all_stdin () in
    let title   = try Title.make   title   with Invalid_argument msg -> Common.exit_with msg in
    let content = try Content.make content with Invalid_argument msg -> Common.exit_with msg in
    match Service.add_note (App_context.service ctx) ~title ~content with
    | Ok note ->
        let niceid = Identifier.to_string (Note.niceid note) in
        let typeid = Typeid.to_string (Note.id note) in
        Printf.printf "Created note: %s (%s)\n" niceid typeid
    | Error err -> Common.exit_with (service_error_msg err))

let run_todo db_override title =
  let db_file = Common.resolve_db_file ~override:db_override in
  let ctx = App_context.init ~db_file ~namespace:None in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let content = Io.read_all_stdin () in
    let title = try Title.make title with Invalid_argument msg -> Common.exit_with msg in
    let content = try Content.make content with Invalid_argument msg -> Common.exit_with msg in
    match Service.add_todo (App_context.service ctx) ~title ~content () with
    | Ok todo ->
        let niceid = Identifier.to_string (Todo.niceid todo) in
        let typeid = Typeid.to_string (Todo.id todo) in
        Printf.printf "Created todo: %s (%s)\n" niceid typeid
    | Error err -> Common.exit_with (service_error_msg err))

let title_arg =
  let doc = "Title of the resource to create." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"TITLE" ~doc)

let note_cmd =
  let term =
    Term.(const run_note $ Common.db_file_arg $ title_arg)
  in
  Cmd.v note_info term

let todo_cmd =
  let term =
    Term.(const run_todo $ Common.db_file_arg $ title_arg)
  in
  Cmd.v todo_info term

let cmd = Cmd.group add_info [note_cmd; todo_cmd]
