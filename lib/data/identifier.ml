module CA = Control.Assert
module CE = Control.Exception
module Namespace = Namespace

type t = {
  namespace : Namespace.t;
  raw_id    : int;
}

let namespace { namespace; _ } = namespace
let raw_id    { raw_id;    _ } = raw_id

let _dash_re = Str.regexp "-"

let _validate_raw_id id =
  CA.requiref (id >= 0) "raw_id must be >= 0, got %d" id;
  id

let make namespace raw_id = {
  namespace = Namespace.of_string namespace;
  raw_id    = _validate_raw_id raw_id;
}

let pp fmt { namespace; raw_id } =
  Format.fprintf fmt "%s-%d" (Namespace.to_string namespace) raw_id

let to_string t = Format.asprintf "%a" pp t

let from_string s =
  match Str.split _dash_re s with
  | [namespace; raw_id_str] -> make namespace (int_of_string raw_id_str)
  | _ -> CE.invalid_argf "Invalid format \"%s\", expected \"namespace-id\"" s
