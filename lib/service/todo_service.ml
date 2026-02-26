module Todo = Repository.Todo

type t = { repo : Todo.t }

type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

let init root = { repo = Repository.Root.todo root }

let add t ~title ~content ?status () =
  Todo.create t.repo ~title ~content ?status ()
  |> Result.map_error (Item_service.map_repo_error ~entity_name:"todo")
