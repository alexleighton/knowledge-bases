(** Namespace acronym generation utilities. *)

type t = string

let namespace_pattern = "^[a-z]+$"
let namespace_re = Str.regexp namespace_pattern

let validate ns =
  let len = String.length ns in
  if len < 1 || len > 5 then
    Error (Printf.sprintf "namespace must be between 1 and 5 characters, got \"%s\"" ns)
  else if not (Str.string_match namespace_re ns 0) then
    Error (Printf.sprintf "namespace must match `%s`, got \"%s\"" namespace_pattern ns)
  else
    Ok ns

let of_string ns =
  match validate ns with
  | Ok ns -> ns
  | Error msg -> invalid_arg msg

let to_string ns = ns

let is_separator = function
  | '-' | '_' | ' ' -> true
  | _ -> false

let of_name name =
  let len = String.length name in
  let rec find_next_non_sep i =
    if i >= len then None
    else if is_separator name.[i] then find_next_non_sep (i + 1)
    else Some i
  in
  let rec gather acc i =
    match find_next_non_sep i with
    | None -> List.rev acc
    | Some start ->
      let rec find_end j =
        if j >= len || is_separator name.[j] then j else find_end (j + 1)
      in
      let end_idx = find_end start in
      let segment = String.sub name start (end_idx - start) in
      gather (segment :: acc) end_idx
  in
  let segments = gather [] 0 in
  let buf = Buffer.create (List.length segments) in
  List.iter
    (fun segment ->
      if String.length segment > 0 then
        Buffer.add_char buf (Char.lowercase_ascii segment.[0]))
    segments;
  Buffer.contents buf
