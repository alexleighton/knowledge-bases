module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Identifier = Kbases.Data.Identifier

let delete_error_msg = function
  | Service.Delete.Blocked_dependency { niceid; dependents } ->
      Printf.sprintf "cannot delete %s: blocked by %s" niceid
        (String.concat ", " dependents)
  | Service.Delete.Service_error err -> Common.service_error_msg err

let result_to_json (r : Service.Delete.delete_result) =
  let open Service.Delete in
  `Assoc [
    "type", `String r.entity_type;
    "niceid", `String (Identifier.to_string r.niceid);
    "relations_removed", `Int r.relations_removed;
  ]

let run first_identifier rest_identifiers force json =
  let identifiers = first_identifier :: rest_identifiers in
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let result =
      match identifiers with
      | [id] -> Service.delete (App_context.service ctx) ~identifier:id ~force
                |> Result.map (fun r -> [r])
      | _ -> Service.delete_many (App_context.service ctx) ~identifiers ~force
    in
    match result with
    | Ok results ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "deleted", `List (List.map result_to_json results);
          ])
        else
          List.iter (fun (r : Service.Delete.delete_result) ->
            let open Service.Delete in
            Printf.printf "Deleted %s: %s\n"
              r.entity_type (Identifier.to_string r.niceid)
          ) results
    | Error err -> Common.exit_with_error ~json (delete_error_msg err))

let first_identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the item to delete." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let rest_identifiers_arg =
  Arg.(value & pos_right 0 string [] & info [] ~docv:"IDENTIFIER")

let force_flag =
  let doc = "Force deletion even if other items have blocking dependencies on this item." in
  Arg.(value & flag & info [ "force" ] ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Delete a single item:";
  `P "  bs delete kb-0";
  `P "Delete multiple items:";
  `P "  bs delete kb-0 kb-1 kb-2";
  `P "Force-delete a blocked item:";
  `P "  bs delete kb-0 --force";
  `P "JSON output:";
  `P "  bs delete kb-0 --json";
]

let cmd_info = Cmd.info "delete"
  ~doc:"Delete items and their relations from the knowledge base."
  ~man:cmd_man

let cmd =
  let term = Term.(const run $ first_identifier_arg $ rest_identifiers_arg
                   $ force_flag $ Common.json_flag) in
  Cmd.v cmd_info term
