module CA = Control.Assert
module CE = Control.Exception

type t = {
  namespace : string;
  raw_id    : int;
}

let namespace { namespace; _ } = namespace
let raw_id    { raw_id;    _ } = raw_id

let _namespace_pattern = "^[a-z]+$"
let _namespace_re = Str.regexp _namespace_pattern
let _dash_re = Str.regexp "-"

let _validate_namespace ns =
  let len = String.length ns in
  CA.require1 (len >= 1 && len <= 5)
    ~msg:"namespace must be between 1 and 5 characters, got \"%s\"" ~arg:ns;
  CA.require2 (Str.string_match _namespace_re ns 0)
    ~msg:"namespace must match `%s`, got \"%s\"" ~arg1:(_namespace_pattern) ~arg2:ns;
  ns

let _validate_raw_id id =
  CA.require1 (id >= 0) ~msg:"raw_id must be >= 0, got %d" ~arg:id;
  id

let make namespace raw_id = {
  namespace = _validate_namespace namespace;
  raw_id    = _validate_raw_id raw_id;
}

let pp fmt { namespace; raw_id } =
  Format.fprintf fmt "%s-%d" namespace raw_id

let to_string t = Format.asprintf "%a" pp t

let from_string s =
  match Str.split _dash_re s with
  | [namespace; raw_id_str] -> make namespace (int_of_string raw_id_str)
  | _ -> CE.invalid_arg1 "Invalid format \"%s\", expected \"namespace-id\"" s
