module NoteRepo = Kbases.Repository.Note
module Niceid = Kbases.Repository.Niceid
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
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

  let note1 = _unwrap_note (NoteRepo.create note_repo
    ~title:(Title.make "Hello") ~content:(Content.make "World") ()) in
  Printf.printf "created niceid=%s status=%s\n"
    (Identifier.to_string (Note.niceid note1))
    (Note.status_to_string (Note.status note1));

  let fetched = _unwrap_note (NoteRepo.get note_repo (Note.id note1)) in
  Printf.printf "fetched title=%s content=%s status=%s\n"
    (Title.to_string (Note.title fetched))
    (Content.to_string (Note.content fetched))
    (Note.status_to_string (Note.status fetched));

  let fetched_by_niceid = _unwrap_note (NoteRepo.get_by_niceid note_repo (Note.niceid note1)) in
  Printf.printf "fetched_by_niceid title=%s status=%s\n"
    (Title.to_string (Note.title fetched_by_niceid))
    (Note.status_to_string (Note.status fetched_by_niceid));

  let updated =
    Note.make
      (Note.id note1)
      (Note.niceid note1)
      (Title.make "Updated")
      (Content.make "Body")
      Note.Archived
  in
  let updated = _unwrap_note (NoteRepo.update note_repo updated) in
  Printf.printf "updated title=%s content=%s status=%s\n"
    (Title.to_string (Note.title updated))
    (Content.to_string (Note.content updated))
    (Note.status_to_string (Note.status updated));

  let () = _unwrap_note (NoteRepo.delete note_repo (Note.niceid note1)) in
  (match NoteRepo.get_by_niceid note_repo (Note.niceid note1) with
   | Error (NoteRepo.Not_found (`Niceid _)) -> print_endline "deleted ok"
   | Ok _ -> print_endline "unexpected lookup result"
   | Error (NoteRepo.Duplicate_niceid _) -> print_endline "unexpected duplicate"
   | Error (NoteRepo.Backend_failure _) -> print_endline "backend failure"
   | Error (NoteRepo.Not_found (`Id _)) -> print_endline "unexpected not found id");

  ignore (Sqlite3.db_close db);
  [%expect {|
    created niceid=nt-0 status=active
    fetched title=Hello content=World status=active
    fetched_by_niceid title=Hello status=active
    updated title=Updated content=Body status=archived
    deleted ok
    |}]

let%expect_test "note repo not found cases" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in
  let missing_id = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
  (match NoteRepo.get note_repo missing_id with
   | Error (NoteRepo.Not_found (`Id _)) -> print_endline "missing by id"
   | Ok _ -> print_endline "unexpected get result"
   | Error (NoteRepo.Not_found (`Niceid _)) -> print_endline "unexpected not found niceid"
   | Error (NoteRepo.Duplicate_niceid _) -> print_endline "unexpected duplicate"
   | Error (NoteRepo.Backend_failure _) -> print_endline "backend failure");
  let missing_niceid = Identifier.make "nt" 42 in
  (match NoteRepo.delete note_repo missing_niceid with
   | Error (NoteRepo.Not_found (`Niceid _)) -> print_endline "missing delete"
   | Ok () -> print_endline "unexpected delete result"
   | Error (NoteRepo.Not_found (`Id _)) -> print_endline "unexpected not found id"
   | Error (NoteRepo.Duplicate_niceid _) -> print_endline "unexpected duplicate"
   | Error (NoteRepo.Backend_failure _) -> print_endline "backend failure");
  ignore (Sqlite3.db_close db);
  [%expect {|
    missing by id
    missing delete
    |}]

let%expect_test "note repo create with explicit status" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in

  let note1 = _unwrap_note (NoteRepo.create note_repo
    ~title:(Title.make "Hello") ~content:(Content.make "World")
    ~status:Note.Archived ()) in
  Printf.printf "created status=%s\n" (Note.status_to_string (Note.status note1));

  ignore (Sqlite3.db_close db);
  [%expect {|
    created status=archived
    |}]

let%expect_test "note repo list filters by status" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in

  ignore (_unwrap_note (NoteRepo.create note_repo
    ~title:(Title.make "Active note") ~content:(Content.make "Body") ()));
  ignore (_unwrap_note (NoteRepo.create note_repo
    ~title:(Title.make "Archived note") ~content:(Content.make "Body")
    ~status:Note.Archived ()));

  let print label statuses =
    match NoteRepo.list note_repo ~statuses with
    | Ok notes ->
        Printf.printf "%s:\n" label;
        List.iter (fun note ->
          Printf.printf "%s %s\n"
            (Identifier.to_string (Note.niceid note))
            (Note.status_to_string (Note.status note))
        ) notes
    | Error _ -> print_endline "list error"
  in

  print "default" [];
  print "active-only" [Note.Active];
  print "archived-only" [Note.Archived];
  print "all" [Note.Active; Note.Archived];

  ignore (Sqlite3.db_close db);
  [%expect {|
    default:
    nt-0 active
    active-only:
    nt-0 active
    archived-only:
    nt-1 archived
    all:
    nt-0 active
    nt-1 archived
    |}]

let%expect_test "note repo list_all returns all statuses" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in

  ignore (_unwrap_note (NoteRepo.create note_repo
    ~title:(Title.make "Active note") ~content:(Content.make "Body") ()));
  ignore (_unwrap_note (NoteRepo.create note_repo
    ~title:(Title.make "Archived note") ~content:(Content.make "Body")
    ~status:Note.Archived ()));

  (match NoteRepo.list_all note_repo with
   | Ok notes ->
       Printf.printf "list_all count=%d\n" (List.length notes);
       let sorted = List.sort (fun a b ->
         compare (Identifier.raw_id (Note.niceid a)) (Identifier.raw_id (Note.niceid b))
       ) notes in
       List.iter (fun note ->
         Printf.printf "%s %s\n"
           (Identifier.to_string (Note.niceid note))
           (Note.status_to_string (Note.status note))
       ) sorted
   | Error _ -> print_endline "list_all error");

  ignore (Sqlite3.db_close db);
  [%expect {|
    list_all count=2
    nt-0 active
    nt-1 archived
    |}]

let%expect_test "note repo delete_all removes everything" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in

  ignore (_unwrap_note (NoteRepo.create note_repo
    ~title:(Title.make "First") ~content:(Content.make "Body") ()));
  ignore (_unwrap_note (NoteRepo.create note_repo
    ~title:(Title.make "Second") ~content:(Content.make "Body") ()));

  let () = _unwrap_note (NoteRepo.delete_all note_repo) in
  (match NoteRepo.list_all note_repo with
   | Ok notes -> Printf.printf "after delete_all count=%d\n" (List.length notes)
   | Error _ -> print_endline "list_all error");

  ignore (Sqlite3.db_close db);
  [%expect {|
    after delete_all count=0
    |}]

let%expect_test "note repo list empty table" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in
  (match NoteRepo.list note_repo ~statuses:[] with
   | Ok notes -> Printf.printf "count=%d\n" (List.length notes)
   | Error _ -> print_endline "unexpected error");
  ignore (Sqlite3.db_close db);
  [%expect {|
    count=0
    |}]

let%expect_test "note repo import with caller-provided TypeId" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in
  let tid = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in

  let note = _unwrap_note (NoteRepo.import note_repo
    ~id:tid ~title:(Title.make "Imported") ~content:(Content.make "Body")
    ~status:Note.Archived ()) in
  Printf.printf "id=%s niceid=%s status=%s\n"
    (Typeid.to_string (Note.id note))
    (Identifier.to_string (Note.niceid note))
    (Note.status_to_string (Note.status note));

  let fetched = _unwrap_note (NoteRepo.get note_repo tid) in
  Printf.printf "fetched title=%s\n" (Title.to_string (Note.title fetched));

  ignore (Sqlite3.db_close db);
  [%expect {|
    id=note_0123456789abcdefghjkmnpqrs niceid=nt-0 status=archived
    fetched title=Imported
    |}]

let%expect_test "note repo import defaults to Active status" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
  let note_repo = _unwrap_note (NoteRepo.init ~db ~niceid_repo) in
  let tid = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in

  let note = _unwrap_note (NoteRepo.import note_repo
    ~id:tid ~title:(Title.make "Default") ~content:(Content.make "Body") ()) in
  Printf.printf "status=%s\n" (Note.status_to_string (Note.status note));

  ignore (Sqlite3.db_close db);
  [%expect {|
    status=active
    |}]
