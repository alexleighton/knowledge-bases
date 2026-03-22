module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service

let file_action_msg = function
  | Service.Lifecycle.Deleted -> "deleted"
  | Service.Lifecycle.Not_found -> "not found"

let agents_md_action_msg = function
  | Service.Lifecycle.File_deleted -> "deleted"
  | Service.Lifecycle.Section_removed -> "section removed"
  | Service.Lifecycle.Section_modified -> "section modified (manual removal required)"
  | Service.Lifecycle.Not_found -> "not found"

let git_exclude_action_msg = function
  | Service.Lifecycle.Entry_removed -> "entry removed"
  | Service.Lifecycle.Entry_not_found -> "entry not found"

let run directory yes json =
  if not yes then
    Common.exit_with_error ~json
      "Uninstall is destructive and not intended for agent use. Pass --yes to confirm."
  else
    match Service.uninstall_kb ~directory with
    | Ok { Service.Lifecycle.directory; database; jsonl; agents_md; git_exclude } ->
        if json then
          Common.print_json (`Assoc [
            "ok", `Bool true;
            "directory", `String directory;
            "database", `String (file_action_msg database);
            "jsonl", `String (file_action_msg jsonl);
            "agents_md", `String (agents_md_action_msg agents_md);
            "git_exclude", `String (git_exclude_action_msg git_exclude);
          ])
        else begin
          Printf.printf "Uninstalled knowledge base:\n";
          Printf.printf "  Directory:   %s\n" directory;
          Printf.printf "  Database:    %s\n" (file_action_msg database);
          Printf.printf "  JSONL:       %s\n" (file_action_msg jsonl);
          Printf.printf "  AGENTS.md:   %s\n" (agents_md_action_msg agents_md);
          Printf.printf "  Git exclude: %s\n" (git_exclude_action_msg git_exclude)
        end
    | Error (Service.Validation_error msg | Service.Repository_error msg) ->
        Common.exit_with_error ~json msg

let directory_arg =
  let doc = "Git repository directory to uninstall from." in
  Arg.(
    value
    & opt (some string) None
    & info [ "d"; "directory" ] ~docv:"DIRECTORY" ~doc)

let yes_flag =
  let doc = "Confirm destructive uninstallation. Required because this permanently \
             removes all knowledge-base artifacts." in
  Arg.(value & flag & info [ "yes" ] ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Uninstall the knowledge base from the current repo:";
  `P "  bs uninstall --yes";
  `P "Uninstall from a specific directory:";
  `P "  bs uninstall --yes -d /path/to/repo";
  `P "Machine-readable JSON output:";
  `P "  bs uninstall --yes --json";
]

let cmd_info = Cmd.info "uninstall"
  ~doc:"Remove all knowledge-base artifacts from a repository."
  ~man:cmd_man

let cmd =
  let term = Term.(const run $ directory_arg $ yes_flag $ Common.json_flag) in
  Cmd.v cmd_info term
