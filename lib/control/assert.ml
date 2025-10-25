open Exception

let require ?(msg = "Requirement not met") condition =
  if not condition then invalid_arg msg

let require1 ?(msg) ?(arg) condition =
  if not condition then
  match msg with 
  | Some msg -> invalid_arg1 msg (Option.get arg)
  | None     -> invalid_arg "Requirement not met"

let require2 ?(msg) ?(arg1) ?(arg2) predicate =
  if not predicate then
  match msg with 
  | Some msg -> invalid_arg2 msg (Option.get arg1) (Option.get arg2)
  | None     -> invalid_arg "Requirement not met"