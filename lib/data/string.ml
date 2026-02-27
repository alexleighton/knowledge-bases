include Stdlib.String

let contains_substring ~needle haystack =
  let nlen = length needle and hlen = length haystack in
  if nlen = 0 then true
  else if nlen > hlen then false
  else
    let rec loop i =
      if i > hlen - nlen then false
      else if sub haystack i nlen = needle then true
      else loop (i + 1)
    in
    loop 0

let rsplit ~sep s =
  match rindex_opt s sep with
  | None -> None
  | Some idx ->
      let left = sub s 0 idx in
      let right = sub s (idx + 1) (length s - idx - 1) in
      Some (left, right)
