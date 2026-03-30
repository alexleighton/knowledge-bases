module Root = Kbases.Repository.Root
module Service = Kbases.Service.Kb_service
module Common = Cmdline_common

type t = {
  root    : Root.t;
  service : Service.t;
}

let init () =
  match Service.open_kb () with
  | Ok (root, service) -> { root; service }
  | Error err ->
      Common.exit_with (Common.service_error_msg err)

let service t = t.service

let config_svc t = Service.config_svc t.service

let close t = Root.close t.root
