module NoteRepo = Kbases.Repository.Note

val create_git_root : string -> string
val starts_with : string -> string -> bool
val normalize : string -> string
val with_chdir : string -> (unit -> 'a) -> 'a
val with_root : string -> (Kbases.Repository.Root.t -> unit) -> unit
val unwrap_note_repo : ('a, NoteRepo.error) result -> 'a
