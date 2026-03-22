module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service

let run show json =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.next (App_context.service ctx) with
    | Ok (Some todo) ->
        Cmd_claim.print_claimed_todo ~show ~json (App_context.service ctx) todo
    | Ok None ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "next", `Null;
          ])
        else
          print_endline "No open unblocked todos"
    | Error (Service.Mutation.Nothing_available { stuck_count }) ->
        if json then begin
          Common.print_json (Cmd_claim.claim_error_json
            (Service.Mutation.Nothing_available { stuck_count }));
          exit 123
        end else
          Common.exit_with ~code:123
            (Printf.sprintf "no available todos (%d open todo(s) blocked)" stuck_count)
    | Error ((Service.Mutation.Not_a_todo _ | Service.Mutation.Not_open _
            | Service.Mutation.Blocked _ | Service.Mutation.Service_error _) as err) ->
        Cmd_claim.exit_claim_error ~json err)

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
