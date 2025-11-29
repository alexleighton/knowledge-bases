module Str = String
module CA = Control.Assert
module CE = Control.Exception

type t = { prefix : string; uuid : Uuidv7.t; suffix : string }

let validate_prefix prefix =
  CA.require_strlen ~min:1 ~max:63 ~msg:"Prefix must be between 1 and 63 characters" prefix;
  CA.require
    ~msg:"Prefix may only contain lowercase ASCII letters or underscores"
    (Str.for_all (fun ch -> Char.is_lowercase ch || ch = '_') prefix);
  CA.require ~msg:"Prefix cannot start with _" (Str.get prefix 0 <> '_');
  CA.require ~msg:"Prefix cannot end with _" (Str.get prefix (Str.length prefix - 1) <> '_')

let validate_suffix suffix =
  CA.require_strlen ~min:26 ~max:26 ~msg:"Suffix must be 26 characters" suffix;
  CA.require ~msg:"Suffix must be base32" (Str.for_all Base32.is_valid_char suffix)

let make prefix =
  validate_prefix prefix;
  let uuid = Uuidv7.make () in
  { prefix; uuid; suffix = Uuidv7.to_uuidm uuid |> Base32.encode }

let to_string { prefix; suffix; _ } = prefix ^ "_" ^ suffix

let of_string str =
  match Str.rsplit ~sep:'_' str with
  | Some (prefix, suffix) ->
      validate_prefix prefix;
      validate_suffix suffix;
        { prefix; suffix; uuid = Base32.decode suffix |> Uuidv7.of_uuidm }
  | _ -> CE.invalid_arg1 "Unable to determine prefix: %s" str

let of_guid prefix uuid = { prefix; uuid; suffix = Uuidv7.to_uuidm uuid |> Base32.encode }

let get_uuid t = t.uuid
let get_prefix t = t.prefix
let get_suffix t = t.suffix
