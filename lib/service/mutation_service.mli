(** Item mutation operations.

    General-purpose update plus convenience commands (resolve, archive)
    for common status transitions. *)

(** Abstract service handle. *)
type t

(** Errors specific to claim and next operations. *)
type claim_error =
  | Not_a_todo of string
  | Not_open of { niceid : string; status : string }
  | Blocked of { niceid : string; blocked_by : string list }
  | Nothing_available of { stuck_count : int }
  | Service_error of Item_service.error

(** [init root] initializes the mutation service from a shared
    {!Repository.Root.t} handle. *)
val init : Repository.Root.t -> t

(** [update t ~identifier ?status ?title ?content ()] applies changes to the
    item identified by [identifier].  At least one of [status], [title], or
    [content] must be provided.

    @return the updated item on success.
    @return [Validation_error] when no change is specified, the status string
            is invalid for the entity type, or the item is not found. *)
val update :
  t ->
  identifier:string ->
  ?status:string ->
  ?title:Data.Title.t ->
  ?content:Data.Content.t ->
  unit ->
  (Item_service.item, Item_service.error) result

(** [next t] selects the first open, unblocked todo (by niceid order) and
    transitions it to [In_Progress].

    @return [Ok None] when no open todos exist.
    @return [Error (Nothing_available _)] when all open todos are blocked. *)
val next : t -> (Data.Todo.t option, claim_error) result

(** [claim t ~identifier] transitions an open, unblocked todo to [In_Progress].

    @return [Not_a_todo] if the item is a note.
    @return [Not_open] if the todo is not in [Open] status.
    @return [Blocked] if the todo has unresolved blocking dependencies. *)
val claim :
  t -> identifier:string -> (Data.Todo.t, claim_error) result

(** [resolve t ~identifier] sets a todo's status to [Done].

    @return [Validation_error] if the item is a note or not found. *)
val resolve :
  t -> identifier:string -> (Data.Todo.t, Item_service.error) result

(** [archive t ~identifier] sets a note's status to [Archived].

    @return [Validation_error] if the item is a todo or not found. *)
val archive :
  t -> identifier:string -> (Data.Note.t, Item_service.error) result

(** [reopen t ~identifier] returns a terminal item to its initial status:
    Done todos become Open, Archived notes become Active.

    @return [Validation_error] if the item is not in a terminal state. *)
val reopen :
  t -> identifier:string -> (Item_service.item, Item_service.error) result

(** [resolve_many t ~identifiers] resolves multiple todos. Short-circuits
    on the first error; the caller must provide a transaction boundary for
    atomicity (see {!Kb_service}). Returns results in input order. *)
val resolve_many :
  t -> identifiers:string list -> (Data.Todo.t list, Item_service.error) result

(** [archive_many t ~identifiers] archives multiple notes. Short-circuits
    on the first error; the caller must provide a transaction boundary for
    atomicity (see {!Kb_service}). Returns results in input order. *)
val archive_many :
  t -> identifiers:string list -> (Data.Note.t list, Item_service.error) result

(** [reopen_many t ~identifiers] reopens multiple terminal items. Short-circuits
    on the first error; the caller must provide a transaction boundary for
    atomicity (see {!Kb_service}). Returns results in input order. *)
val reopen_many :
  t -> identifiers:string list -> (Item_service.item list, Item_service.error) result
