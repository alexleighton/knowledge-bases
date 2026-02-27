(** Knowledge-base lifecycle management.

    Initialization, discovery, and opening of knowledge bases. Independent of
    all other service modules. *)

(** Errors that can arise from lifecycle operations. *)
type error =
  | Repository_error of string
  | Validation_error of string

(** Result of knowledge-base initialization. *)
type init_result = {
  directory : string;
  namespace : string;
  db_file   : string;
}

(** Database filename used for knowledge bases (e.g. [".kbases.db"]). *)
val db_filename : string

(** [resolve_directory dir] resolves and validates the target directory for a
    knowledge base. When [dir] is [None], the current git repository root is
    used. When [Some path], the path must exist, be a directory, and be a git
    repository root. *)
val resolve_directory : string option -> (string, error) result

(** [resolve_namespace ~directory ns] resolves the namespace for a knowledge
    base. When [ns] is [Some name], the name is validated directly. When
    [None], a namespace is derived from the git repository name of
    [directory]. *)
val resolve_namespace :
  directory:string -> string option -> (string, error) result

(** [init_kb ~directory ~namespace] initializes a knowledge base in a git
    repository, creates [.kbases.db], and persists the effective namespace. *)
val init_kb :
  directory:string option ->
  namespace:string option ->
  (init_result, error) result

(** JSONL filename used for the git-tracked snapshot (e.g. [".kbases.jsonl"]). *)
val jsonl_filename : string

(** [open_kb ()] finds the git root from the current directory and opens the
    knowledge base at [.kbases.db]. Returns the root handle and the git root
    directory. Callers must close the root when done. *)
val open_kb : unit -> (Repository.Root.t * string, error) result
