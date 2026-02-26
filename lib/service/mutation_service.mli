(** Item mutation operations.

    General-purpose update plus convenience commands (resolve, archive)
    for common status transitions. *)

(** Abstract service handle. *)
type t

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

(** [resolve t ~identifier] sets a todo's status to [Done].

    @return [Validation_error] if the item is a note or not found. *)
val resolve :
  t -> identifier:string -> (Data.Todo.t, Item_service.error) result

(** [archive t ~identifier] sets a note's status to [Archived].

    @return [Validation_error] if the item is a todo or not found. *)
val archive :
  t -> identifier:string -> (Data.Note.t, Item_service.error) result
