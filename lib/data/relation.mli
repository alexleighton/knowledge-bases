(** Relation — a typed link between two entities.

    A relation connects a source entity to a target entity with a named
    kind.  Relations can be unidirectional or bidirectional depending
    on their kind. *)

(** Abstract type of relations. *)
type t

(** [make ~source ~target ~kind ~bidirectional] constructs a relation. *)
val make :
  source:Uuid.Typeid.t ->
  target:Uuid.Typeid.t ->
  kind:Relation_kind.t ->
  bidirectional:bool ->
  t

(** [source t] returns the source entity TypeId. *)
val source : t -> Uuid.Typeid.t

(** [target t] returns the target entity TypeId. *)
val target : t -> Uuid.Typeid.t

(** [kind t] returns the relation kind. *)
val kind : t -> Relation_kind.t

(** [is_bidirectional t] returns [true] when the relation is
    traversable in both directions. *)
val is_bidirectional : t -> bool

(** [pp fmt t] pretty-prints the relation. *)
val pp : Format.formatter -> t -> unit

(** [show t] returns the string that {!pp} would print. *)
val show : t -> string
