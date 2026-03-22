module type S = sig
  type t
  type status
  type id = Uuid.Typeid.t

  val entity_name : string

  val make_id : unit -> id

  val make :
    id ->
    Identifier.t ->
    Title.t ->
    Content.t ->
    status ->
    created_at:Timestamp.t ->
    updated_at:Timestamp.t ->
    t

  val id : t -> id
  val niceid : t -> Identifier.t
  val title : t -> Title.t
  val content : t -> Content.t
  val status : t -> status
  val created_at : t -> Timestamp.t
  val updated_at : t -> Timestamp.t

  val with_status : t -> status -> t
  val with_title : t -> Title.t -> t
  val with_content : t -> Content.t -> t
  val with_updated_at : t -> Timestamp.t -> t

  val status_to_string : status -> string
  val status_from_string : string -> status

  val default_status : status
  val default_excluded_status : status

  val pp : Format.formatter -> t -> unit
  val show : t -> string
end
