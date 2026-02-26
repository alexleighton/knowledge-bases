module type ENTITY = sig
  include Data.Entity.S with type id = Data.Uuid.Typeid.t

  val table_name : string
  val default_status : status
  val default_excluded_status : status
  val id_to_string : id -> string
  val id_of_string : string -> id
end

type error =
  | Not_found of [ `Id of Data.Uuid.Typeid.t | `Niceid of Data.Identifier.t ]
  | Duplicate_niceid of Data.Identifier.t
  | Backend_failure of string

module Make (E : ENTITY) : sig
  type t

  type nonrec error = error =
    | Not_found of [ `Id of Data.Uuid.Typeid.t | `Niceid of Data.Identifier.t ]
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
end
