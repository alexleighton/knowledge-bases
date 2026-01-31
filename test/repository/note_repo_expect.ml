module NoteRepo = Kbases.Repository.Note
module Niceid = Kbases.Repository.Niceid
module Note = Kbases.Data.Note
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid

let _unwrap_note = function
  | Ok v -> v
  | Error _ -> failwith "unexpected error"

let _unwrap_niceid = function
  | Ok v -> v
  | Error (Niceid.Backend_failure msg) -> failwith ("backend failure: " ^ msg)

let%expect_test "note repo create/get/update/delete happy path" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in

  let note1 = _unwrap_note (NoteRepo.create note_repo ~title:"Hello" ~content:"World") in
  Printf.printf "created niceid=%s\n" (Identifier.to_string (Note.niceid note1));

  let fetched = _unwrap_note (NoteRepo.get note_repo (Note.id note1)) in
  Printf.printf "fetched title=%s content=%s\n" (Note.title fetched) (Note.content fetched);

  let fetched_by_niceid = _unwrap_note (NoteRepo.get_by_niceid note_repo (Note.niceid note1)) in
  Printf.printf "fetched_by_niceid title=%s\n" (Note.title fetched_by_niceid);

  let updated =
    Note.make
      (Note.id note1)
      (Note.niceid note1)
      "Updated"
      "Body"
  in
  let updated = _unwrap_note (NoteRepo.update note_repo updated) in
  Printf.printf "updated title=%s content=%s\n" (Note.title updated) (Note.content updated);

  let () = _unwrap_note (NoteRepo.delete note_repo (Note.niceid note1)) in
  (match NoteRepo.get_by_niceid note_repo (Note.niceid note1) with
   | Error (NoteRepo.Not_found (`Niceid _)) -> print_endline "deleted ok"
   | _ -> print_endline "unexpected lookup result");

  ignore (Sqlite3.db_close db);
  [%expect {|
    created niceid=nt-0
    fetched title=Hello content=World
    fetched_by_niceid title=Hello
    updated title=Updated content=Body
    deleted ok
    |}]

let%expect_test "note repo not found cases" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in
  let missing_id = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
  (match NoteRepo.get note_repo missing_id with
   | Error (NoteRepo.Not_found (`Id _)) -> print_endline "missing by id"
   | _ -> print_endline "unexpected get result");
  let missing_niceid = Identifier.make "nt" 42 in
  (match NoteRepo.delete note_repo missing_niceid with
   | Error (NoteRepo.Not_found (`Niceid _)) -> print_endline "missing delete"
   | _ -> print_endline "unexpected delete result");
  ignore (Sqlite3.db_close db);
  [%expect {|
    missing by id
    missing delete
    |}]

