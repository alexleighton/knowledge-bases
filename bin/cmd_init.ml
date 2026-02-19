module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service

let run directory namespace =
  match Service.init_kb ~directory ~namespace with
  | Ok ({ Service.directory; namespace; db_file } : Service.init_result) ->
      Printf.printf "Initialised knowledge base:\n";
      Printf.printf "  Directory: %s\n" directory;
      Printf.printf "  Namespace: %s\n" namespace;
      Printf.printf "  Database:  %s\n" db_file
  | Error (Service.Validation_error msg | Service.Repository_error msg) ->
      Common.exit_with msg

let directory_arg =
  let doc = "Git repository directory for the knowledge base." in
  Arg.(
    value
    & opt (some string) None
    & info [ "d"; "directory" ] ~docv:"DIRECTORY" ~doc)

let namespace_arg =
  let doc = "Namespace identifier (1-5 lowercase letters)." in
  Arg.(
    value
    & opt (some string) None
    & info [ "n"; "namespace" ] ~docv:"NAMESPACE" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "bs init";
  `P "bs init -d /path/to/repo -n ns";
]

let cmd_info = Cmd.info "init" ~doc:"Initialise a new knowledge base." ~man:cmd_man

let cmd =
  let term = Term.(const run $ directory_arg $ namespace_arg) in
  Cmd.v cmd_info term
