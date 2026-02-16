(** Application context — initializes and manages the dependency graph.

    This module is the composition root for the CLI: it opens the database,
    initialises every repository, and hands the resulting handles to the
    service layer. On any initialisation error the process exits. *)

(** Abstract application context. *)
type t

(** [init ~db_file ~namespace] opens the database, initialises all
    repositories, and constructs the service layer. Exits the process on
    failure. *)
val init : db_file:string -> namespace:string option -> t

(** [service t] returns the knowledge-base service handle. *)
val service : t -> Kbases.Service.Kb_service.t

(** [close t] releases resources held by the context. *)
val close : t -> unit
