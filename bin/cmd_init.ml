module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service

let agents_md_msg = function
  | Service.Created -> "created"
  | Service.Appended -> "appended to existing file"
  | Service.Already_present -> "section already present"

let git_exclude_msg = function
  | Service.Excluded -> "added to .git/info/exclude"
  | Service.Already_excluded -> "already in .git/info/exclude"

let run directory namespace json =
  match Service.init_kb ~directory ~namespace with
  | Ok ({ Service.directory; namespace; db_file; agents_md; git_exclude } : Service.init_result) ->
      if json then
        Common.print_json (`Assoc [
          "ok", `Bool true;
          "directory", `String directory;
          "namespace", `String namespace;
          "db_file", `String db_file;
          "agents_md", `String (agents_md_msg agents_md);
          "git_exclude", `String (git_exclude_msg git_exclude);
        ])
      else begin
        Printf.printf "Initialised knowledge base:\n";
        Printf.printf "  Directory:   %s\n" directory;
        Printf.printf "  Namespace:   %s\n" namespace;
        Printf.printf "  Database:    %s\n" db_file;
        Printf.printf "  AGENTS.md:   %s\n" (agents_md_msg agents_md);
        Printf.printf "  Git exclude: %s\n" (git_exclude_msg git_exclude)
      end
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
  let term = Term.(const run $ directory_arg $ namespace_arg $ Common.json_flag) in
  Cmd.v cmd_info term
