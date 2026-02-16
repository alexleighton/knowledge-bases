(** IO helpers used by command-line frontends. *)

(** [read_all_stdin ()] consumes stdin until EOF and returns the trimmed
    contents. *)
val read_all_stdin : unit -> string
