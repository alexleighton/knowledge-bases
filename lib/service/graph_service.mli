(** Graph traversal over the relation graph.

    Provides BFS reachability and connected-component queries.
    Application-level traversal using {!Repository.Relation}. *)

(** Abstract service handle. *)
type t

(** Direction of traversal. *)
type direction = Outgoing | Incoming | Any

(** [init root] initializes the graph service. *)
val init : Repository.Root.t -> t

(** [reachable_from t ~typeid ~kind ~direction] returns all TypeIds
    reachable from [typeid] via BFS, following relations of the given
    [kind] (or all kinds when [None]) in the given [direction].

    The starting [typeid] is not included in the result. *)
val reachable_from :
  t ->
  typeid:Data.Uuid.Typeid.t ->
  kind:Data.Relation_kind.t option ->
  direction:direction ->
  (Data.Uuid.Typeid.t list, Item_service.error) result

(** [connected_component t ~typeid] returns all TypeIds in the same
    connected component as [typeid], following all relation kinds in
    both directions.

    The starting [typeid] is included in the result. *)
val connected_component :
  t ->
  typeid:Data.Uuid.Typeid.t ->
  (Data.Uuid.Typeid.t list, Item_service.error) result
