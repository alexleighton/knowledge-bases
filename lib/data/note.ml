module CA = Control.Assert
module Typeid = Uuid.Typeid

let _typeid_prefix = "note"

type id = Typeid.t

let show_id = Typeid.to_string
let pp_id fmt id = Format.pp_print_string fmt (show_id id)

type t = {
  id      : id;
  niceid  : Identifier.t;
  title   : string;
  content : string;
}
[@@deriving show]

let _validate_title title =
  let len = String.length title in
  CA.requiref (len >= 1 && len <= 100)
    "title must be between 1 and 100 characters, got %d" len;
  title

let _validate_content content =
  let len = String.length content in
  CA.requiref (len >= 1 && len <= 10000)
    "content must be between 1 and 10000 characters, got %d" len;
  content

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
  title   = _validate_title title;
  content = _validate_content content;
}
