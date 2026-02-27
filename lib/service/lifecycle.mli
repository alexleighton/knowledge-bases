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
