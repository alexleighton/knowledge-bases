module Arg = Cmdliner.Arg

module Git = Kbases.Control.Git

let db_file_arg =
  let doc =
    "Override the SQLite database file path. Defaults to <repo>/.kbases.db when \
     running inside a git repository."
  in
  Arg.(value & opt (some string) None & info [ "db-file" ] ~doc ~docv:"FILE")

let resolve_db_file ~override =
  match override with
  | Some path -> path
  | None ->
      (match Git.find_repo_root () with
      | Some root -> Filename.concat root ".kbases.db"
      | None ->
          prerr_endline
            "Error: Not in a git repository. Use --db-file to specify database \
             location.";
          exit 1)
