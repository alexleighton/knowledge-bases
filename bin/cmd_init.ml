module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service

let agents_md_msg = function
  | Service.Lifecycle.Created -> "created"
  | Service.Lifecycle.Appended -> "appended to existing file"
  | Service.Lifecycle.Already_present -> "section already present"

let git_exclude_msg = function
  | Service.Lifecycle.Excluded -> "added to .git/info/exclude"
  | Service.Lifecycle.Already_excluded -> "already in .git/info/exclude"

let run directory namespace gc_max_age json =
  match Service.init_kb ~directory ~namespace ~gc_max_age with
  | Ok ({ Service.Lifecycle.directory; namespace; db_file; agents_md; git_exclude }) ->
      let gc_age_str = match gc_max_age with Some s -> s | None -> "30d" in
      let gc_label = match gc_max_age with
        | Some _ -> gc_age_str
        | None -> gc_age_str ^ " (default)"
      in
      if json then
        Common.print_json (`Assoc [
          "ok", `Bool true;
          "directory", `String directory;
          "namespace", `String namespace;
          "db_file", `String db_file;
          "agents_md", `String (agents_md_msg agents_md);
          "git_exclude", `String (git_exclude_msg git_exclude);
          "gc_max_age", `String gc_age_str;
        ])
      else begin
        Printf.printf "Initialised knowledge base:\n";
        Printf.printf "  Directory:   %s\n" directory;
        Printf.printf "  Namespace:   %s\n" namespace;
        Printf.printf "  Database:    %s\n" db_file;
        Printf.printf "  AGENTS.md:   %s\n" (agents_md_msg agents_md);
        Printf.printf "  Git exclude: %s\n" (git_exclude_msg git_exclude);
        Printf.printf "  GC max age:  %s\n" gc_label
      end
  | Error (Service.Validation_error msg | Service.Repository_error msg) ->
      Common.exit_with_error ~json msg

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

let gc_max_age_arg =
  let doc = "GC max age threshold (e.g. 14d, 30d). Defaults to 30d." in
  Arg.(value & opt (some string) None & info [ "gc-max-age" ] ~docv:"AGE" ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Initialise in the current git repo:";
  `P "  bs init";
  `P "Specify directory and namespace:";
  `P "  bs init -d /path/to/repo -n ns";
  `P "Set custom GC max age:";
  `P "  bs init --gc-max-age 14d";
  `P "Machine-readable JSON output:";
  `P "  bs init --json";
]

let cmd_info = Cmd.info "init" ~doc:"Initialise a new knowledge base." ~man:cmd_man

let cmd =
  let term = Term.(const run $ directory_arg $ namespace_arg $ gc_max_age_arg $ Common.json_flag) in
  Cmd.v cmd_info term
