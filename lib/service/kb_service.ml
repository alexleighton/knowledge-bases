module Note = Note_service
module Todo = Todo_service
module Query = Query_service
module Mutation = Mutation_service

type t = {
  notes    : Note.t;
  todos    : Todo.t;
  query    : Query.t;
  mutation : Mutation.t;
}

type error = Item_service.error =
  | Repository_error of string
  | Validation_error of string

type item = Item_service.item =
  | Todo_item of Data.Todo.t
  | Note_item of Data.Note.t

type init_result = Lifecycle.init_result = {
  directory : string;
  namespace : string;
  db_file   : string;
}

let init root = {
  notes    = Note.init root;
  todos    = Todo.init root;
  query    = Query.init root;
  mutation = Mutation.init root;
}

let db_filename = Lifecycle.db_filename

let map_lifecycle_error = function
  | Lifecycle.Repository_error msg -> Repository_error msg
  | Lifecycle.Validation_error msg -> Validation_error msg

let map_note_error = function
  | Note.Repository_error msg -> Repository_error msg

let map_todo_error = function
  | Todo.Repository_error msg -> Repository_error msg

let open_kb () =
  Lifecycle.open_kb ()
  |> Result.map (fun root -> (root, init root))
  |> Result.map_error map_lifecycle_error

let init_kb ~directory ~namespace =
  Lifecycle.init_kb ~directory ~namespace
  |> Result.map_error map_lifecycle_error

let add_note t ~title ~content =
  Note.add t.notes ~title ~content
  |> Result.map_error map_note_error

let add_todo t ~title ~content ?status () =
  Todo.add t.todos ~title ~content ?status ()
  |> Result.map_error map_todo_error

let list t ~entity_type ~statuses =
  Query.list t.query ~entity_type ~statuses

let show t ~identifier =
  Query.show t.query ~identifier

let update t ~identifier ?status ?title ?content () =
  Mutation.update t.mutation ~identifier ?status ?title ?content ()

let resolve t ~identifier =
  Mutation.resolve t.mutation ~identifier

let archive t ~identifier =
  Mutation.archive t.mutation ~identifier
