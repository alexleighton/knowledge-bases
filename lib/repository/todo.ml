include Entity_repo.Make(struct
  include Data.Todo
  let table_name = "todo"
  let default_status = Data.Todo.Open
  let default_excluded_status = Data.Todo.Done
  let id_to_string = Data.Uuid.Typeid.to_string
  let id_of_string = Data.Uuid.Typeid.of_string
end)
