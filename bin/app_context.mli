(** Application context — initializes and manages the dependency graph.

    This module is the composition root for the CLI: it opens the database,
    initialises every repository, and hands the resulting handles to the
    service layer. On any initialisation error the process exits. *)

(** Abstract application context. *)
type t

(** [init ()] finds the git root, opens the knowledge base at [.kbases.db],
    and constructs the service layer. Exits the process on failure. *)
val init : unit -> t

(** [service t] returns the knowledge-base service handle. *)
val service : t -> Kbases.Service.Kb_service.t

(** [close t] releases resources held by the context. *)
val close : t -> unit
