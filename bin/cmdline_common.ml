module Service = Kbases.Service.Kb_service

let service_error_msg = function
  | Service.Repository_error text | Service.Validation_error text -> text

let exit_with msg =
  prerr_endline ("Error: " ^ msg);
  exit 1

let json_flag =
  let doc = "Output result as JSON." in
  Cmdliner.Arg.(value & flag & info [ "json" ] ~doc)

let print_json json =
  print_endline (Yojson.Safe.to_string json)

let depends_on_opt =
  let doc = "Target identifier. Creates a unidirectional depends-on relation." in
  Cmdliner.Arg.(value & opt_all string [] & info [ "depends-on" ] ~docv:"TARGET" ~doc)

let related_to_opt =
  let doc = "Target identifier. Creates a bidirectional related-to relation." in
  Cmdliner.Arg.(value & opt_all string [] & info [ "related-to" ] ~docv:"TARGET" ~doc)

let uni_opt =
  let doc =
    "User-defined unidirectional relation. Value is KIND,TARGET (e.g. designed-by,kb-1)."
  in
  Cmdliner.Arg.(value & opt_all (pair ~sep:',' string string) []
    & info [ "uni" ] ~docv:"KIND,TARGET" ~doc)

let bi_opt =
  let doc =
    "User-defined bidirectional relation. Value is KIND,TARGET (e.g. reviews,kb-1)."
  in
  Cmdliner.Arg.(value & opt_all (pair ~sep:',' string string) []
    & info [ "bi" ] ~docv:"KIND,TARGET" ~doc)
