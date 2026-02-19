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
      let msg =
        match err with
        | Service.Repository_error text | Service.Validation_error text -> text
      in
      Common.exit_with msg

let service t = t.service

let close t = Root.close t.root
