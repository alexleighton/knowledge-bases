include Stdlib.String

let rsplit ~sep s =
  match rindex_opt s sep with
  | None -> None
  | Some idx ->
      let left = sub s 0 idx in
      let right = sub s (idx + 1) (length s - idx - 1) in
      Some (left, right)
