include Stdlib.String

let for_all pred s =
  let len = length s in
  let rec loop i =
    if i >= len then true
    else if pred (get s i) then loop (i + 1)
    else false
  in
  loop 0

let rsplit ~sep s =
  match rindex_opt s sep with
  | None -> None
  | Some idx ->
      let left = sub s 0 idx in
      let right = sub s (idx + 1) (length s - idx - 1) in
      Some (left, right)
