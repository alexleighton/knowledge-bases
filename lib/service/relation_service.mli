(** Relation creation service.

    Resolves identifiers, validates the relation kind, persists the
    relation, and returns a result suitable for CLI display. *)

(** Abstract service handle. *)
type t

(** Specification for a single relation to create in a bulk operation. *)
type relate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
  blocking      : bool;
}

(** Result of a successful relate operation. *)
type relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  target_type   : string;
  target_title  : Data.Title.t;
}

(** [init root] initializes the relation service from a shared
    {!Repository.Root.t} handle. *)
val init : Repository.Root.t -> t

(** [build_specs ~depends_on ~related_to ~uni ~bi ~blocking] constructs a
    {!relate_spec} list from the four relation categories.

    - [depends_on]: target identifiers for unidirectional ["depends-on"] relations.
      Always blocking regardless of [~blocking].
    - [related_to]: target identifiers for bidirectional ["related-to"] relations.
    - [uni]: [(kind, target)] pairs for user-defined unidirectional relations.
    - [bi]: [(kind, target)] pairs for user-defined bidirectional relations.
    - [blocking]: when [true], marks non-depends-on relations as blocking. *)
val build_specs :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  blocking:bool ->
  relate_spec list

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
  blocking:bool ->
  (relate_result, Item_service.error) result

(** [relate_many t ~source ~specs] validates all specs (resolves targets,
    parses kinds) before inserting any relation. Fails fast on the first
    validation error with no side effects. Caller is responsible for
    transaction scope.

    @return [Ok results] on success (one entry per spec, in order).
    @return [Validation_error] if any target is not found or any kind is invalid.
    @return [Repository_error] on storage failure. *)
val relate_many :
  t ->
  source:string ->
  specs:relate_spec list ->
  (relate_result list, Item_service.error) result

(** Specification for a single relation to remove. *)
type unrelate_spec = {
  target        : string;
  kind          : string;
  bidirectional : bool;
}

(** [build_unrelate_specs ~depends_on ~related_to ~uni ~bi] constructs an
    {!unrelate_spec} list from the four relation categories.

    Same categories as {!build_specs} but without the [blocking] parameter,
    which is irrelevant for removal. *)
val build_unrelate_specs :
  depends_on:string list ->
  related_to:string list ->
  uni:(string * string) list ->
  bi:(string * string) list ->
  unrelate_spec list

(** Result of a successful unrelate operation. *)
type unrelate_result = {
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  kind          : Data.Relation_kind.t;
  bidirectional : bool;
}

(** [unrelate_many t ~source ~specs] removes relations matching the given
    specs. Validates all specs before deleting any. *)
val unrelate_many :
  t ->
  source:string ->
  specs:unrelate_spec list ->
  (unrelate_result list, Item_service.error) result

(** [find_blockers t todo] returns the niceids of unresolved todos that
    block [todo] via blocking relations.  Returns an empty list when
    [todo] is not blocked. *)
val find_blockers :
  t -> Data.Todo.t -> (string list, Item_service.error) result
