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

let run show json =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.next (App_context.service ctx) with
    | Ok (Some todo) ->
        let niceid = Identifier.to_string (Todo.niceid todo) in
        let typeid = Typeid.to_string (Todo.id todo) in
        if show then begin
          match Service.show (App_context.service ctx) ~identifier:niceid with
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
          | Error err -> Common.exit_with (Common.service_error_msg err)
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
    | Ok None ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "next", `Null;
          ])
        else
          print_endline "No open unblocked todos"
    | Error (Service.Nothing_available { stuck_count }) ->
        if json then begin
          Common.print_json (`Assoc [
            "ok", `Bool false;
            "reason", `String "nothing_available";
            "stuck_count", `Int stuck_count;
          ]);
          exit 123
        end else
          Common.exit_with ~code:123
            (Printf.sprintf "no available todos (%d open todo(s) blocked)" stuck_count)
    | Error (Service.Not_a_todo _ | Service.Not_open _ | Service.Blocked _) ->
        Common.exit_with "unexpected error"
    | Error (Service.Service_error (ItemService.Repository_error msg
                                   | ItemService.Validation_error msg)) ->
        if json then begin
          Common.print_json (`Assoc [
            "ok", `Bool false;
            "reason", `String "error";
            "message", `String msg;
          ]);
          exit 1
        end else
          Common.exit_with msg)

let show_flag =
  let doc = "After claiming, display full item details (like bs show)." in
  Arg.(value & flag & info [ "show" ] ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Claim the next available todo:";
  `P "  bs next";
  `P "Claim and show full details:";
  `P "  bs next --show";
]

let cmd_info = Cmd.info "next" ~doc:"Claim the next available open todo." ~man:cmd_man

let cmd =
  let term = Term.(const run $ show_flag $ Common.json_flag) in
  Cmd.v cmd_info term
