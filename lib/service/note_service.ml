module Note = Repository.Note

type t = { repo : Note.t }

type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

let init root = { repo = Repository.Root.note root }

let add t ~title ~content =
  Note.create t.repo ~title ~content ()
  |> Result.map_error (Item_service.map_repo_error ~entity_name:"note")
