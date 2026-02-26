module Note = Repository.Note

type t = { repo : Note.t }

type error =
  | Repository_error of string

let init root = { repo = Repository.Root.note root }

let repository_error_label = function
  | Note.Backend_failure msg -> Repository_error msg
  | Note.Duplicate_niceid niceid ->
      Repository_error ("duplicate nice id " ^ Data.Identifier.to_string niceid)
  | Note.Not_found _ -> Repository_error "note not found"

let add t ~title ~content =
  Note.create t.repo ~title ~content ()
  |> Result.map_error repository_error_label
