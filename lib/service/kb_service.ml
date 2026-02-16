module Note = Repository.Note

type t = {
  note_repo : Note.t;
}

type error =
  | Repository_error of string
  | Validation_error of string

let init root =
  { note_repo = Repository.Root.note root }

let repository_error_label = function
  | Note.Backend_failure msg -> Repository_error msg
  | Note.Duplicate_niceid niceid ->
      Repository_error ("duplicate nice id " ^ Data.Identifier.to_string niceid)
  | Note.Not_found _ -> Repository_error "note not found"

let add_note t ~title ~content =
  try
    Note.create t.note_repo ~title ~content
    |> Result.map_error repository_error_label
  with Invalid_argument msg -> Error (Validation_error msg)
