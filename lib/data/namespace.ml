(** Namespace acronym generation utilities. *)

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
