module CA = Control.Assert
module CE = Control.Exception
module Typeid = Uuid.Typeid

let _typeid_prefix = "note"

type id = Typeid.t

type status = Active | Archived [@@deriving show]

let status_to_string = function Active -> "active" | Archived -> "archived"

let status_from_string = function
  | "active" -> Active
  | "archived" -> Archived
  | s -> CE.invalid_argf "Invalid status \"%s\"" s

let status_of_string s =
  try Ok (status_from_string s)
  with Invalid_argument msg -> Error msg

let show_id = Typeid.to_string
let pp_id fmt id = Format.pp_print_string fmt (show_id id)

type t = {
  id         : id;
  niceid     : Identifier.t;
  title      : Title.t;
  content    : Content.t;
  status     : status;
  created_at : Timestamp.t;
  updated_at : Timestamp.t;
}
[@@deriving show]

let _validate_id typeid =
  let prefix = Typeid.get_prefix typeid in
  CA.requiref (String.equal prefix _typeid_prefix)
    "note TypeId prefix must be \"%s\", got \"%s\""
    _typeid_prefix prefix;
  typeid

let make_id () = Typeid.make _typeid_prefix

let make id niceid title content status ~created_at ~updated_at = {
  id         = _validate_id id;
  niceid     = niceid;
  title      = title;
  content    = content;
  status     = status;
  created_at = created_at;
  updated_at = updated_at;
}

let id         { id;         _ } = id
let niceid     { niceid;     _ } = niceid
let title      { title;      _ } = title
let content    { content;    _ } = content
let status     { status;     _ } = status
let created_at { created_at; _ } = created_at
let updated_at { updated_at; _ } = updated_at

let with_status     t status     = { t with status }
let with_title      t title      = { t with title }
let with_content    t content    = { t with content }
let with_updated_at t updated_at = { t with updated_at }
