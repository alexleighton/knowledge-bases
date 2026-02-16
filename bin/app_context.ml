module Root = Kbases.Repository.Root
module Service = Kbases.Service.Kb_service

type t = {
  root    : Root.t;
  service : Service.t;
}

let init ~db_file ~namespace =
  match Root.init ~db_file ~namespace with
  | Ok root ->
      let service = Service.init root in
      { root; service }
  | Error (Root.Backend_failure msg) ->
      Printf.eprintf "Error: %s\n" msg;
      exit 1

let service t = t.service

let close t = Root.close t.root
