let require ?(msg = "Requirement not met") condition =
  if not condition then invalid_arg msg

let requiref condition fmt =
  Printf.ksprintf (fun msg -> if not condition then invalid_arg msg) fmt

let require_strlen ?msg ~min ~max value =
  let len = String.length value in
  match msg with
  | Some msg -> require ~msg (len >= min && len <= max)
  | None ->
      requiref (len >= min && len <= max)
        "String length must be between %d and %d, got %d" min max len
