module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common

let identifier_arg =
  let doc = "Niceid (e.g. kb-0) or TypeId of the todo to close." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Mark a todo as done (alias for resolve):";
  `P "  bs close kb-0";
]

let cmd_info = Cmd.info "close" ~doc:"Mark a todo as done (alias for resolve)." ~man:cmd_man

let cmd =
  let term = Term.(const Cmd_resolve.run $ identifier_arg $ Common.json_flag) in
  Cmd.v cmd_info term
