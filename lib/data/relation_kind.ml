module CA = Control.Assert

type t = string

let _valid_char = function
  | 'a' .. 'z' | '0' .. '9' | '-' -> true
  | _ -> false

let _valid_format s =
  let len = String.length s in
  len > 0
  && s.[0] <> '-'
  && s.[len - 1] <> '-'
  && String.to_seq s |> Seq.for_all _valid_char

let make s =
  CA.require_strlen ~name:"relation kind" ~min:1 ~max:50 s;
  CA.require
    ~msg:"relation kind must match [a-z0-9][a-z0-9-]* and not end with '-'"
    (_valid_format s);
  s

let to_string t = t
let equal = String.equal
let pp fmt t = Format.pp_print_string fmt t
let show t = t
