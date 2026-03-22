include Stdlib.Result

let sequence results =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | Ok v :: rest -> loop (v :: acc) rest
    | (Error _ as e) :: _ -> e
  in
  loop [] results

let traverse f xs =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | x :: rest ->
        match f x with
        | Ok v -> loop (v :: acc) rest
        | Error _ as e -> e
  in
  loop [] xs
