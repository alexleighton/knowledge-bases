module CA = Control.Assert

type t = string

let pp fmt t = Format.fprintf fmt "%S" t
let show t = Printf.sprintf "%S" t

let make s =
  CA.require_strlen ~name:"title" ~min:1 ~max:100 s;
  s

let to_string t = t
