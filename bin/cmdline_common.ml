module Service = Kbases.Service.Kb_service

let service_error_msg = function
  | Service.Repository_error text | Service.Validation_error text -> text

let exit_with ?(code = 1) msg =
  prerr_endline ("Error: " ^ msg);
  exit code

let print_json json =
  print_endline (Yojson.Safe.to_string json)

let exit_with_error ?(code = 1) ~json msg =
  if json then begin
    print_json (`Assoc [
      "ok", `Bool false;
      "reason", `String "error";
      "message", `String msg;
    ]);
    exit code
  end else
    exit_with ~code msg

let resolve_content_source content_opt =
  match content_opt with
  | Some content ->
      if Kbases.Control.Io.stdin_is_piped () then begin
        let piped = Kbases.Control.Io.read_all_stdin () in
        if piped <> "" then
          exit_with "Cannot specify both --content and stdin input."
      end;
      Some content
  | None ->
      if Kbases.Control.Io.stdin_is_piped () then
        let raw = Kbases.Control.Io.read_all_stdin () in
        if raw = "" then None else Some raw
      else None

let item_summary_json ~entity_type ~niceid =
  `Assoc [
    "type", `String entity_type;
    "niceid", `String (Kbases.Data.Identifier.to_string niceid);
  ]

let json_flag =
  let doc = "Output result as JSON." in
  Cmdliner.Arg.(value & flag & info [ "json" ] ~doc)

let rest_identifiers_arg =
  Cmdliner.Arg.(value & pos_right 0 string [] & info [] ~docv:"IDENTIFIER")

let depends_on_opt =
  let doc = "Create a unidirectional depends-on relation to $(i,TARGET). \
             Shows as outgoing on the source and incoming on the target. Repeatable." in
  Cmdliner.Arg.(value & opt_all string [] & info [ "depends-on" ] ~docv:"TARGET" ~doc)

let related_to_opt =
  let doc = "Create a bidirectional related-to relation with $(i,TARGET). \
             Shows as outgoing from both endpoints. Repeatable." in
  Cmdliner.Arg.(value & opt_all string [] & info [ "related-to" ] ~docv:"TARGET" ~doc)

let uni_opt =
  let doc =
    "Create a unidirectional relation with an arbitrary kind name. \
     Value is $(i,KIND,TARGET) (e.g. designed-by,kb-1). \
     Shows as outgoing on the source and incoming on the target. Repeatable."
  in
  Cmdliner.Arg.(value & opt_all (pair ~sep:',' string string) []
    & info [ "uni" ] ~docv:"KIND,TARGET" ~doc)

let bi_opt =
  let doc =
    "Create a bidirectional relation with an arbitrary kind name. \
     Value is $(i,KIND,TARGET) (e.g. reviews,kb-1). \
     Shows as outgoing from both endpoints. Repeatable."
  in
  Cmdliner.Arg.(value & opt_all (pair ~sep:',' string string) []
    & info [ "bi" ] ~docv:"KIND,TARGET" ~doc)

let blocking_flag =
  let doc = "Mark non-depends-on relations as blocking. \
             Dependencies (--depends-on) are always blocking." in
  Cmdliner.Arg.(value & flag & info [ "blocking" ] ~doc)
