include Cmdline_common

module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term

let root_doc = "Knowledge base management CLI."

let root_man = [
  `S "DESCRIPTION";
  `P "Track todos, notes, and relations in a local knowledge base. \
      Designed for use by coding agents and humans alike.";
  `S "EXAMPLES";
  `P "Initialise a knowledge base:";
  `P "  bs init";
  `P "Create items with inline content or stdin:";
  `P "  bs add todo \"Fix CI\" --content \"Investigate flaky test\"";
  `P "  echo \"Meeting notes\" | bs add note \"Standup\"";
  `P "Create a todo linked to an existing item:";
  `P "  bs add todo \"Subtask\" --content \"Details\" --depends-on kb-0";
  `P "Browse and inspect:";
  `P "  bs list todo --status open";
  `P "  bs list --available";
  `P "  bs show kb-0 kb-1";
  `P "Claim and work on todos:";
  `P "  bs next";
  `P "  bs next --show";
  `P "  bs claim kb-0 --show";
  `P "Edit items:";
  `P "  bs update kb-0 --title \"Revised title\"";
  `P "  bs update kb-0 --content \"Revised plan\"";
  `P "Complete and archive:";
  `P "  bs resolve kb-0 kb-1";
  `P "  bs close kb-0";
  `P "  bs archive kb-5 kb-6";
  `P "Link items after creation:";
  `P "  bs relate kb-2 --related-to kb-3";
  `P "Sync for git:";
  `P "  bs flush";
  `P "Remove a knowledge base:";
  `P "  bs uninstall --yes";
]

let root_info = Cmd.info "bs" ~doc:root_doc ~man:root_man

let root_cmd =
  let default = Term.(ret (const (`Help (`Auto, None)))) in
  Cmd.group ~default root_info [
  Cmd_init.cmd; Cmd_uninstall.cmd;
  Cmd_add.cmd; Cmd_list.cmd; Cmd_show.cmd;
  Cmd_update.cmd; Cmd_claim.cmd; Cmd_next.cmd;
  Cmd_resolve.cmd; Cmd_close.cmd; Cmd_archive.cmd;
  Cmd_reopen.cmd; Cmd_delete.cmd;
  Cmd_relate.cmd; Cmd_unrelate.cmd;
  Cmd_flush.cmd; Cmd_rebuild.cmd; Cmd_gc.cmd; Cmd_config.cmd;
]

let () = exit (Cmd.eval root_cmd)
