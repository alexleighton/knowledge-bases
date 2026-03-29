module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo

val with_git_root : string -> (string -> 'a) -> 'a
val with_temp_dir : string -> (string -> 'a) -> 'a
val normalize : string -> string
val with_chdir : string -> (unit -> 'a) -> 'a
val with_root : string -> (Kbases.Repository.Root.t -> unit) -> unit
val unwrap_note_repo : ('a, NoteRepo.error) result -> 'a
val unwrap_todo_repo : ('a, TodoRepo.error) result -> 'a
val pp_item_error : Kbases.Service.Item_service.error -> unit
val with_service :
  (Kbases.Repository.Root.t -> 'svc) ->
  (Kbases.Repository.Root.t -> 'svc -> unit) ->
  unit
val query_db :
  Kbases.Repository.Root.t ->
  string ->
  (int * Sqlite3.Data.t) list ->
  (Sqlite3.stmt -> string) ->
  unit
val query_rows :
  Kbases.Repository.Root.t ->
  string ->
  (int * Sqlite3.Data.t) list ->
  unit
val query_count : Kbases.Repository.Root.t -> string -> unit
val make_blocking_rel :
  source:Kbases.Data.Todo.t -> target:Kbases.Data.Todo.t -> Kbases.Data.Relation.t
val query_relations : Kbases.Repository.Root.t -> unit
val print_query_items : Kbases.Service.Query_service.item list -> unit
val unwrap_query_items :
  (Kbases.Service.Query_service.list_result, Kbases.Service.Query_service.error) result ->
  Kbases.Service.Query_service.item list
val pp_lifecycle_error : Kbases.Service.Lifecycle.error -> unit
val expect_lifecycle_ok :
  ('a, Kbases.Service.Lifecycle.error) result -> ('a -> unit) -> unit
val expect_service_ok :
  ('a, Kbases.Service.Kb_service.error) result -> ('a -> unit) -> unit
val with_open_kb :
  (Kbases.Repository.Root.t -> Kbases.Service.Kb_service.t -> unit) -> unit
