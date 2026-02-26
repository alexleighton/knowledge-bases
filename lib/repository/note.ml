include Entity_repo.Make(struct
  include Data.Note
  let table_name = "note"
  let default_status = Data.Note.Active
  let default_excluded_status = Data.Note.Archived
  let id_to_string = Data.Uuid.Typeid.to_string
  let id_of_string = Data.Uuid.Typeid.of_string
end)
