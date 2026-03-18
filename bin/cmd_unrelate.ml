module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Identifier = Kbases.Data.Identifier
module Relation_kind = Kbases.Data.Relation_kind

let run source depends_on related_to uni bi json =
  let specs = Service.build_unrelate_specs ~depends_on ~related_to ~uni ~bi in
  if specs = [] then
    Common.exit_with_error ~json
      "at least one of --depends-on, --related-to, --uni, or --bi is required";
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.unrelate (App_context.service ctx) ~source ~specs with
    | Ok results ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "removed", `List (List.map (fun (r : Service.unrelate_result) ->
              let dir = if r.Service.bidirectional then "bidirectional"
                        else "unidirectional" in
              `Assoc [
                "source", `String (Identifier.to_string r.Service.source_niceid);
                "kind", `String (Relation_kind.to_string r.Service.kind);
                "target", `String (Identifier.to_string r.Service.target_niceid);
                "directionality", `String dir;
              ]) results);
          ])
        else
          List.iter (fun (r : Service.unrelate_result) ->
            Printf.printf "Unrelated: %s %s %s (removed)\n"
              (Identifier.to_string r.Service.source_niceid)
              (Relation_kind.to_string r.Service.kind)
              (Identifier.to_string r.Service.target_niceid))
            results
    | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

let source_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the source item." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"SOURCE" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Remove a dependency:";
  `P "  bs unrelate kb-0 --depends-on kb-1";
  `P "Remove a bidirectional link:";
  `P "  bs unrelate kb-0 --related-to kb-1";
  `P "JSON output:";
  `P "  bs unrelate kb-0 --depends-on kb-1 --json";
]

let cmd_info = Cmd.info "unrelate"
  ~doc:"Remove relations from a source item."
  ~man:cmd_man

let cmd =
  let term =
    Term.(const run $ source_arg $ Common.depends_on_opt $ Common.related_to_opt
          $ Common.uni_opt $ Common.bi_opt $ Common.json_flag)
  in
  Cmd.v cmd_info term
