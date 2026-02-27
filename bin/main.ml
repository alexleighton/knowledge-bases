include Cmdline_common

module Cmd = Cmdliner.Cmd

let root_doc = "Knowledge base management CLI."

let root_man = [
  `S "DESCRIPTION";
  `P "Manage a local knowledge base backed by SQLite.";
  `S "COMMANDS";
  `P "init        Initialise a new knowledge base in a git repository.";
  `P "add note    Create a note from stdin.";
  `P "add todo    Create a todo from stdin.";
  `P "list        List todos and notes.";
  `P "show        Display full details of an item.";
  `P "update      Update an existing item.";
  `P "resolve     Mark a todo as done.";
  `P "archive     Mark a note as archived.";
  `P "relate      Create a relation between two items.";
  `P "flush       Flush SQLite data to .kbases.jsonl.";
  `P "rebuild     Rebuild SQLite from .kbases.jsonl.";
  `S "EXAMPLES";
  `P "bs init";
  `P "echo \"Content\" | bs add note \"Title\"";
  `P "echo \"Content\" | bs add todo \"Title\"";
]

let root_info = Cmd.info "bs" ~doc:root_doc ~man:root_man

let root_cmd = Cmd.group root_info [
  Cmd_init.cmd; Cmd_add.cmd; Cmd_list.cmd; Cmd_show.cmd;
  Cmd_update.cmd; Cmd_resolve.cmd; Cmd_archive.cmd; Cmd_relate.cmd;
  Cmd_flush.cmd; Cmd_rebuild.cmd;
]

let () = exit (Cmd.eval root_cmd)
