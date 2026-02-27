(** Relation creation service.

    Resolves identifiers, validates the relation kind, persists the
    relation, and returns a result suitable for CLI display. *)

(** Abstract service handle. *)
type t

(** Result of a successful relate operation. *)
type relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
}

(** [init root] initializes the relation service from a shared
    {!Repository.Root.t} handle. *)
val init : Repository.Root.t -> t

(** [relate t ~source ~target ~kind ~bidirectional] creates a relation
    between the items identified by [source] and [target].

    Both identifiers are resolved as niceids or TypeIds (see
    {!Item_service.find}).  [kind] is validated as a
    {!Data.Relation_kind.t}.

    @return [Ok relate_result] on success.
    @return [Validation_error] if either item is not found, the kind is
            invalid, or the relation already exists.
    @return [Repository_error] on storage failure. *)
val relate :
  t ->
  source:string ->
  target:string ->
  kind:string ->
  bidirectional:bool ->
  (relate_result, Item_service.error) result
