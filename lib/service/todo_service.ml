module Todo = Repository.Todo

type t = { repo : Todo.t }

type error =
  | Repository_error of string

let init root = { repo = Repository.Root.todo root }

let todo_repository_error_label = function
  | Todo.Backend_failure msg -> Repository_error msg
  | Todo.Duplicate_niceid niceid ->
      Repository_error ("duplicate nice id " ^ Data.Identifier.to_string niceid)
  | Todo.Not_found _ -> Repository_error "todo not found"

let add t ~title ~content ?status () =
  Todo.create t.repo ~title ~content ?status ()
  |> Result.map_error todo_repository_error_label
