include Cmdline_common

module Cmd = Cmdliner.Cmd

let root_doc = "Knowledge base management CLI."

let root_info = Cmd.info "bs" ~doc:root_doc

let root_cmd = Cmd.group root_info [ Cmd_add.cmd ]

let () = exit (Cmd.eval root_cmd)
