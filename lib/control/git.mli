(** Git repository utilities. *)

(** [is_git_root dir] returns [true] when [dir] directly contains a [.git] entry. *)
val is_git_root : string -> bool

(**
   [find_repo_root ?start_dir ()] traverses upward from
   [start_dir] (defaults to the current working directory) looking
   for a [.git] entry. Returns the path whose directory contains
   [.git], or [None] if no git repository is found.
*)
val find_repo_root : ?start_dir:string -> unit -> string option

(**
   [repo_name path] extracts the repository name from [path] by returning
   its basename.
*)
val repo_name : string -> string
