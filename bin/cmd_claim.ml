module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module ItemService = Kbases.Service.Item_service
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid

let claim_error_msg = function
  | Service.Not_a_todo id ->
      Printf.sprintf "%s is not a todo" id
  | Service.Not_open { niceid; status } ->
      Printf.sprintf "%s is not open (status: %s)" niceid status
  | Service.Blocked { niceid; blocked_by } ->
      Printf.sprintf "%s is blocked by %s" niceid (String.concat ", " blocked_by)
  | Service.Nothing_available _ ->
      "no available todos"
  | Service.Service_error (ItemService.Repository_error msg)
  | Service.Service_error (ItemService.Validation_error msg) -> msg

let claim_error_json = function
  | Service.Not_a_todo id ->
      `Assoc ["ok", `Bool false; "reason", `String "not_a_todo";
              "identifier", `String id]
  | Service.Not_open { niceid; status } ->
      `Assoc ["ok", `Bool false; "reason", `String "not_open";
              "niceid", `String niceid; "status", `String status]
  | Service.Blocked { niceid; blocked_by } ->
      `Assoc ["ok", `Bool false; "reason", `String "blocked";
              "niceid", `String niceid;
              "blocked_by", `List (List.map (fun s -> `String s) blocked_by)]
  | Service.Nothing_available { stuck_count } ->
      `Assoc ["ok", `Bool false; "reason", `String "nothing_available";
              "stuck_count", `Int stuck_count]
  | Service.Service_error (ItemService.Repository_error msg)
  | Service.Service_error (ItemService.Validation_error msg) ->
      `Assoc ["ok", `Bool false; "reason", `String "error";
              "message", `String msg]

let print_claimed_todo ~show ~json (service : Service.t) (todo : Todo.t) =
  let niceid = Identifier.to_string (Todo.niceid todo) in
  let typeid = Typeid.to_string (Todo.id todo) in
  if show then begin
    match Service.show service ~identifier:niceid with
    | Ok result ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "action", `String "claimed";
            "item", Cmd_show.item_to_json result;
          ])
        else begin
          Printf.printf "Claimed todo: %s\n" niceid;
          Cmd_show.format_show_result result
        end
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err)
  end else begin
    if json then
      Common.print_json (`Assoc [
        "ok", `Bool true;
        "action", `String "claimed";
        "type", `String "todo";
        "niceid", `String niceid;
        "typeid", `String typeid;
      ])
    else
      Printf.printf "Claimed todo: %s  %s\n" niceid
        (Title.to_string (Todo.title todo))
  end

let exit_claim_error ~json err =
  if json then begin
    Common.print_json (claim_error_json err);
    exit 1
  end else
    Common.exit_with (claim_error_msg err)

let run identifier show json =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.claim (App_context.service ctx) ~identifier with
    | Ok todo ->
        print_claimed_todo ~show ~json (App_context.service ctx) todo
    | Error err -> exit_claim_error ~json err)

let identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the todo to claim." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let show_flag =
  let doc = "After claiming, display full item details (like bs show)." in
  Arg.(value & flag & info [ "show" ] ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Claim an open todo:";
  `P "  bs claim kb-0";
  `P "Claim and show full details:";
  `P "  bs claim kb-0 --show";
]

let cmd_info = Cmd.info "claim" ~doc:"Claim an open todo by setting its status to in-progress." ~man:cmd_man

let cmd =
  let term = Term.(const run $ identifier_arg $ show_flag $ Common.json_flag) in
  Cmd.v cmd_info term
