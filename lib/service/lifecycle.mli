(** Knowledge-base lifecycle management.

    Initialization, discovery, opening, and teardown of knowledge bases.
    Independent of all other service modules. *)

(** Errors that can arise from lifecycle operations. *)
type error =
  | Repository_error of string
  | Validation_error of string

(** Result of a file deletion attempt. *)
type file_action = Deleted | Not_found

(** Action taken on AGENTS.md during initialization. *)
type agents_md_action = Created | Appended | Already_present

(** Action taken on .git/info/exclude during initialization. *)
type git_exclude_action = Excluded | Already_excluded

(** Result of removing the AGENTS.md section during uninstall. *)
type agents_md_uninstall_action =
  | File_deleted | Section_removed | Section_modified | Not_found

(** Result of removing the .git/info/exclude entry. *)
type git_exclude_uninstall_action = Entry_removed | Entry_not_found

(** Result of knowledge-base initialization. *)
type init_result = {
  directory   : string;
  namespace   : string;
  db_file     : string;
  mode        : string;
  agents_md   : agents_md_action;
  git_exclude : git_exclude_action;
}

(** [init_kb ~directory ~namespace ~gc_max_age ~mode] initializes a knowledge
    base in a git repository, creates [.kbases.db], and persists the effective
    namespace.  When [gc_max_age] is provided, stores it in the config table.
    [mode] selects ["local"] (SQLite only) or ["shared"] (SQLite + JSONL sync);
    defaults to ["shared"] when [None]. *)
val init_kb :
  directory:string option ->
  namespace:string option ->
  gc_max_age:string option ->
  mode:string option ->
  (init_result, error) result

(** [uninstall_file path] deletes [path] if it exists and returns [Deleted],
    or returns [Not_found] if the file does not exist. *)
val uninstall_file : string -> file_action

(** [uninstall_agents_md ~directory] reverses the effect of [install_agents_md].
    Deletes the file if it contains only the template, removes the appended
    section if the template appears as a suffix, or reports [Section_modified]
    if the heading is present but the body has been edited. *)
val uninstall_agents_md : directory:string -> agents_md_uninstall_action

(** [uninstall_git_exclude ~directory] removes the [.kbases.db] entry from
    [.git/info/exclude]. Returns [Entry_not_found] if the file does not exist
    or does not contain the entry. *)
val uninstall_git_exclude : directory:string -> git_exclude_uninstall_action

(** Result of knowledge-base uninstallation. *)
type uninstall_result = {
  directory   : string;
  database    : file_action;
  jsonl       : file_action;
  agents_md   : agents_md_uninstall_action;
  git_exclude : git_exclude_uninstall_action;
}

(** [uninstall_kb ~directory] removes all knowledge-base artifacts from the
    given git repository. Returns [Error] only if directory resolution fails;
    individual artifacts that are already absent are reported as not-found
    in the result. *)
val uninstall_kb : directory:string option -> (uninstall_result, error) result

(** JSONL filename used for the git-tracked snapshot (e.g. [".kbases.jsonl"]). *)
val jsonl_filename : string

(** [open_kb ()] finds the git root from the current directory and opens the
    knowledge base at [.kbases.db]. Returns the root handle and the git root
    directory. Callers must close the root when done. *)
val open_kb : unit -> (Repository.Root.t * string, error) result
