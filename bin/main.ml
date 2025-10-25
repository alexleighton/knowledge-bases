module Id = Kbases.Data.Identifier

let () =
  let id = Id.make "test" 42 in
  Printf.printf "Hello from knowledge-bases! (%s)\n" (Id.to_string id);
