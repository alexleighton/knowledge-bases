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
