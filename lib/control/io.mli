(** IO helpers used by command-line frontends. *)

(** [read_file path] reads the entire contents of the file at [path]. *)
val read_file : string -> string

(** [write_file ~path ~contents] writes [contents] to the file at [path],
    creating or overwriting it. *)
val write_file : path:string -> contents:string -> unit

(** [read_all_stdin ()] consumes stdin until EOF and returns the trimmed
    contents. *)
val read_all_stdin : unit -> string

(** [stdin_is_piped ()] returns [true] when stdin is a pipe or redirected from
    a file, [false] on an interactive terminal. *)
val stdin_is_piped : unit -> bool
