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

(** Whether the entry was added or was already present. *)
type exclude_result = Added | Already_present

(** [add_exclude ~directory entry] ensures [entry] appears as a line in
    [.git/info/exclude] under [directory].  Creates [.git/info/] and the
    exclude file if they do not exist. *)
val add_exclude : directory:string -> string -> exclude_result

(** Whether the entry was removed or was not present. *)
type remove_exclude_result = Removed | Remove_not_found

(** [remove_exclude ~directory entry] removes [entry] from
    [.git/info/exclude] under [directory].  Returns [Remove_not_found]
    if the file does not exist or does not contain the entry. *)
val remove_exclude : directory:string -> string -> remove_exclude_result
