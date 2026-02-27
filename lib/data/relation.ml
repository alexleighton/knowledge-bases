type t = {
  source        : Uuid.Typeid.t;
  target        : Uuid.Typeid.t;
  kind          : Relation_kind.t;
  bidirectional : bool;
}

let make ~source ~target ~kind ~bidirectional =
  { source; target; kind; bidirectional }

let source t = t.source
let target t = t.target
let kind t = t.kind
let is_bidirectional t = t.bidirectional

let pp fmt t =
  Format.fprintf fmt "(%s) -[%s%s]-> (%s)"
    (Uuid.Typeid.to_string t.source)
    (Relation_kind.to_string t.kind)
    (if t.bidirectional then " <->" else "")
    (Uuid.Typeid.to_string t.target)

let show t =
  Format.asprintf "%a" pp t
