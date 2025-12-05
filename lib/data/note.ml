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
  CA.require1 (len >= 1 && len <= 100)
    ~msg:"title must be between 1 and 100 characters, got %d" ~arg:len;
  title

let _validate_content content =
  let len = String.length content in
  CA.require1 (len >= 1 && len <= 10000)
    ~msg:"content must be between 1 and 10000 characters, got %d" ~arg:len;
  content

let _validate_id typeid =
  let prefix = Typeid.get_prefix typeid in
  CA.require2 (String.equal prefix _typeid_prefix)
    ~msg:"note TypeId prefix must be \"%s\", got \"%s\""
    ~arg1:_typeid_prefix ~arg2:prefix;
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
