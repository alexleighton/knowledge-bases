module NoteRepo = Kbases.Repository.Note
module TodoRepo = Kbases.Repository.Todo

val create_git_root : string -> string
val starts_with : string -> string -> bool
val normalize : string -> string
val with_chdir : string -> (unit -> 'a) -> 'a
val with_root : string -> (Kbases.Repository.Root.t -> unit) -> unit
val unwrap_repo : entity_name:string -> ('a, Kbases.Repository.Entity_repo.error) result -> 'a
val unwrap_note_repo : ('a, NoteRepo.error) result -> 'a
val unwrap_todo_repo : ('a, TodoRepo.error) result -> 'a
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
