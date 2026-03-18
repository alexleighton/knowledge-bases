type t =
  | Todo_item of Todo.t
  | Note_item of Note.t

let typeid = function
  | Todo_item t -> Todo.id t
  | Note_item n -> Note.id n

let niceid = function
  | Todo_item t -> Todo.niceid t
  | Note_item n -> Note.niceid n

let entity_type = function
  | Todo_item _ -> "todo"
  | Note_item _ -> "note"

let title = function
  | Todo_item t -> Todo.title t
  | Note_item n -> Note.title n

let created_at = function
  | Todo_item t -> Todo.created_at t
  | Note_item n -> Note.created_at n

let updated_at = function
  | Todo_item t -> Todo.updated_at t
  | Note_item n -> Note.updated_at n
