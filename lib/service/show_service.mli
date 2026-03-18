(** Single-item detail queries with relation context.

    Looks up an item by identifier and enriches it with its outgoing
    and incoming relations. *)

(** Abstract service handle. *)
type t

(** Unified item type. *)
type item = Data.Item.t =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

(** A single relation entry in show output. *)
type relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  blocking    : bool option;
}

(** Result of a show query. *)
type show_result = {
  item     : item;
  outgoing : relation_entry list;
  incoming : relation_entry list;
}

(** [init root] initializes the show service. *)
val init : Repository.Root.t -> t

(** [show t ~identifier] looks up a single item by niceid or TypeId,
    including its outgoing and incoming relations. *)
val show : t -> identifier:string -> (show_result, Item_service.error) result

(** [show_many t ~identifiers] looks up multiple items. *)
val show_many :
  t -> identifiers:string list -> (show_result list, Item_service.error) result
