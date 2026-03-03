module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module Identifier = Kbases.Data.Identifier

let run source depends_on related_to uni bi json =
  let specs = Service.build_specs ~depends_on ~related_to ~uni ~bi in
  if specs = [] then
    Common.exit_with
      "at least one of --depends-on, --related-to, --uni, or --bi is required";
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    match Service.relate (App_context.service ctx) ~source ~specs with
    | Ok results ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "relations", `List (List.map (fun { Service.relation = rel;
                                               source_niceid; target_niceid; _ } ->
              let dir = if Relation.is_bidirectional rel then "bidirectional"
                        else "unidirectional" in
              `Assoc [
                "source", `String (Identifier.to_string source_niceid);
                "kind", `String (Relation_kind.to_string (Relation.kind rel));
                "target", `String (Identifier.to_string target_niceid);
                "directionality", `String dir;
              ]) results);
          ])
        else
          List.iter (fun { Service.relation = rel; source_niceid;
                           target_niceid; _ } ->
            let dir = if Relation.is_bidirectional rel then "bidirectional"
                      else "unidirectional" in
            Printf.printf "Related: %s %s %s (%s)\n"
              (Identifier.to_string source_niceid)
              (Relation_kind.to_string (Relation.kind rel))
              (Identifier.to_string target_niceid)
              dir)
            results
    | Error err -> Common.exit_with (Common.service_error_msg err))

let source_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the source item." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"SOURCE" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "bs relate kb-0 --depends-on kb-1";
  `P "bs relate kb-0 --related-to kb-1";
  `P "bs relate kb-0 --uni designed-by,kb-1";
  `P "bs relate kb-0 --bi reviews,kb-1";
  `P "bs relate kb-0 --depends-on kb-1 --depends-on kb-2";
]

let cmd_info = Cmd.info "relate" ~doc:"Create relations from a source item to one or more targets." ~man:cmd_man

let cmd =
  let term =
    Term.(const run $ source_arg $ Common.depends_on_opt $ Common.related_to_opt $ Common.uni_opt $ Common.bi_opt $ Common.json_flag)
  in
  Cmd.v cmd_info term
