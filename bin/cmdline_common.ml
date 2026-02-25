module Service = Kbases.Service.Kb_service

let service_error_msg = function
  | Service.Repository_error text | Service.Validation_error text -> text

let exit_with msg =
  prerr_endline ("Error: " ^ msg);
  exit 1
