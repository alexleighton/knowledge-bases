module CA = Control.Assert
module Typeid = Uuid.Typeid

let _typeid_prefix = "note"

type id = Typeid.t

let show_id = Typeid.to_string
let pp_id fmt id = Format.pp_print_string fmt (show_id id)

type t = {
  id      : id;
  niceid  : Identifier.t;
  title   : Title.t;
  content : Content.t;
}
[@@deriving show]

let _validate_id typeid =
  let prefix = Typeid.get_prefix typeid in
  CA.requiref (String.equal prefix _typeid_prefix)
    "note TypeId prefix must be \"%s\", got \"%s\""
    _typeid_prefix prefix;
  typeid

let make_id () = Typeid.make _typeid_prefix

let id      { id;      _ } = id
let niceid  { niceid;  _ } = niceid
let title   { title;   _ } = title
let content { content; _ } = content

let make id niceid title content = {
  id      = _validate_id id;
  niceid  = niceid;
  title   = title;
  content = content;
}
