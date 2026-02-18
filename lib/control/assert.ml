let require ?(msg = "Requirement not met") condition =
  if not condition then invalid_arg msg

let requiref condition fmt =
  Printf.ksprintf (fun msg -> if not condition then invalid_arg msg) fmt

let require_strlen ~name ~min ~max value =
  let len = String.length value in
  requiref (len >= min && len <= max)
    "%s must be between %d and %d characters, got %d" name min max len
