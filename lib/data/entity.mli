(** Shared module type for domain entities (todos, notes).

    Both {!Todo} and {!Note} satisfy this signature structurally. *)

module type S = sig
  type t
  type id
  type status

  val make_id : unit -> id
  val make : id -> Identifier.t -> Title.t -> Content.t -> status -> t

  val id : t -> id
  val niceid : t -> Identifier.t
  val title : t -> Title.t
  val content : t -> Content.t
  val status : t -> status

  val with_status : t -> status -> t
  val with_title : t -> Title.t -> t
  val with_content : t -> Content.t -> t

  val status_to_string : status -> string
  val status_from_string : string -> status
end
