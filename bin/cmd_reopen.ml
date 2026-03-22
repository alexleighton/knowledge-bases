module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Identifier = Kbases.Data.Identifier

let item_to_json_and_msg = function
  | Service.Todo_item todo ->
      let niceid = Identifier.to_string (Todo.niceid todo) in
      (`Assoc ["type", `String "todo"; "niceid", `String niceid],
       Printf.sprintf "Reopened todo: %s" niceid)
  | Service.Note_item note ->
      let niceid = Identifier.to_string (Note.niceid note) in
      (`Assoc ["type", `String "note"; "niceid", `String niceid],
       Printf.sprintf "Reactivated note: %s" niceid)

let run first_identifier rest_identifiers json =
  let identifiers = first_identifier :: rest_identifiers in
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let result =
      Service.reopen_many (App_context.service ctx) ~identifiers
    in
    match result with
    | Ok items ->
        let pairs = List.map item_to_json_and_msg items in
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "reopened", `List (List.map fst pairs);
          ])
        else
          List.iter (fun (_, msg) -> print_endline msg) pairs
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

let first_identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the item to reopen." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Reopen a resolved todo:";
  `P "  bs reopen kb-0";
  `P "Reopen multiple items:";
  `P "  bs reopen kb-0 kb-1 kb-2";
  `P "Reactivate an archived note:";
  `P "  bs reopen kb-1";
  `P "JSON output:";
  `P "  bs reopen kb-0 --json";
]

let cmd_info = Cmd.info "reopen"
  ~doc:"Return a terminal item to its initial status (Open/Active)."
  ~man:cmd_man

let cmd =
  let term = Term.(const run $ first_identifier_arg $ Common.rest_identifiers_arg
                   $ Common.json_flag) in
  Cmd.v cmd_info term
