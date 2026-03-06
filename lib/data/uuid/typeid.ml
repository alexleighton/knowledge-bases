module Str = String
module CA = Control.Assert
module CE = Control.Exception

type t = { prefix : string; suffix : string }

let validate_prefix prefix =
  CA.require_strlen ~name:"prefix" ~min:1 ~max:63 prefix;
  CA.require
    ~msg:"Prefix may only contain lowercase ASCII letters or underscores"
    (Str.for_all (fun ch -> Char.is_lowercase ch || ch = '_') prefix);
  CA.require ~msg:"Prefix cannot start with _" (Str.get prefix 0 <> '_');
  CA.require ~msg:"Prefix cannot end with _" (Str.get prefix (Str.length prefix - 1) <> '_')

let validate_suffix suffix =
  CA.require_strlen ~name:"suffix" ~min:26 ~max:26 suffix;
  CA.require ~msg:"Suffix must be base32" (Str.for_all Base32.is_valid_char suffix)

let make prefix =
  validate_prefix prefix;
  let uuid = Uuidv7.make () in
  { prefix; suffix = Uuidv7.to_uuidm uuid |> Base32.encode }

let of_guid prefix uuid = { prefix; suffix = Uuidv7.to_uuidm uuid |> Base32.encode }

let to_string { prefix; suffix; _ } = prefix ^ "_" ^ suffix

let of_string str =
  match Str.rsplit ~sep:'_' str with
  | Some (prefix, suffix) ->
      validate_prefix prefix;
      validate_suffix suffix;
        (* Validate that the suffix decodes to a valid 128-bit UUID. *)
        ignore (Base32.decode suffix |> Uuidv7.of_uuidm);
        { prefix; suffix }
  | _ -> CE.invalid_argf "Unable to determine prefix: %s" str

let parse s =
  try Ok (of_string s)
  with Invalid_argument msg -> Error msg

let get_prefix t = t.prefix
let get_suffix t = t.suffix
