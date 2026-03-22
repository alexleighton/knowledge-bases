(** Generic entity repository functor.

    [Make(E)] produces a CRUD repository for entity type [E], backed by a
    SQLite table named [E.entity_name]. *)

module Make (E : Data.Entity.S) : sig
  type t

  type error =
    | Not_found of [ `Id of E.id | `Niceid of Data.Identifier.t ]
    | Duplicate_niceid of Data.Identifier.t
    | Backend_failure of string

  val init :
    db:Sqlite3.db ->
    niceid_repo:Niceid.t ->
    (t, error) result

  val create :
    t ->
    title:Data.Title.t ->
    content:Data.Content.t ->
    ?status:E.status ->
    ?now:(unit -> Data.Timestamp.t) ->
    unit ->
    (E.t, error) result

  val import :
    t ->
    id:E.id ->
    title:Data.Title.t ->
    content:Data.Content.t ->
    ?status:E.status ->
    created_at:Data.Timestamp.t ->
    updated_at:Data.Timestamp.t ->
    unit ->
    (E.t, error) result

  val get : t -> E.id -> (E.t, error) result
  val get_by_niceid : t -> Data.Identifier.t -> (E.t, error) result
  val update : t -> E.t -> (E.t, error) result
  val delete : t -> Data.Identifier.t -> (unit, error) result

  val list :
    t ->
    statuses:E.status list ->
    (E.t list, error) result

  val list_all : t -> (E.t list, error) result
  val delete_all : t -> (unit, error) result
end
