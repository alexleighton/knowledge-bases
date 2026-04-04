module NoteRepo = Kbases.Repository.Note
module Niceid = Kbases.Repository.Niceid
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid
module Timestamp = Kbases.Data.Timestamp

let with_db = Test_helpers.with_db
let query_rows = Test_helpers.query_rows_raw
let query_count = Test_helpers.query_count_raw
let unwrap_note = Test_helpers.unwrap_note
let unwrap_niceid = Test_helpers.unwrap_niceid

let pp_error = function
  | NoteRepo.Not_found (`Id id) ->
      Printf.printf "not found by id: %s\n" (Typeid.to_string id)
  | NoteRepo.Not_found (`Niceid niceid) ->
      Printf.printf "not found by niceid: %s\n" (Identifier.to_string niceid)
  | NoteRepo.Duplicate_niceid niceid ->
      Printf.printf "duplicate niceid: %s\n" (Identifier.to_string niceid)
  | NoteRepo.Backend_failure msg ->
      Printf.printf "backend failure: %s\n" msg

let with_note_repo f =
  with_db (fun db ->
    let niceid_repo = unwrap_niceid (Niceid.init ~db ~namespace:"nt") in
    let note_repo = unwrap_note (NoteRepo.init ~db ~niceid_repo) in
    f db note_repo)

let%expect_test "create assigns niceid and persists row" =
  with_note_repo (fun db note_repo ->
    let note = unwrap_note (NoteRepo.create note_repo
      ~title:(Title.make "Hello") ~content:(Content.make "World") ()) in
    Printf.printf "niceid=%s status=%s\n"
      (Identifier.to_string (Note.niceid note))
      (Note.status_to_string (Note.status note));
    query_count db "note";
    query_rows db "SELECT niceid, title, content, status FROM note" []);
  [%expect {|
    niceid=nt-0 status=active
    note=1
    nt-0|Hello|World|active
    |}]

let%expect_test "get and get_by_niceid return created note" =
  with_note_repo (fun _db note_repo ->
    let note = unwrap_note (NoteRepo.create note_repo
      ~title:(Title.make "Hello") ~content:(Content.make "World") ()) in
    let fetched = unwrap_note (NoteRepo.get note_repo (Note.id note)) in
    Printf.printf "get title=%s content=%s status=%s\n"
      (Title.to_string (Note.title fetched))
      (Content.to_string (Note.content fetched))
      (Note.status_to_string (Note.status fetched));
    let by_niceid = unwrap_note (NoteRepo.get_by_niceid note_repo (Note.niceid note)) in
    Printf.printf "get_by_niceid title=%s status=%s\n"
      (Title.to_string (Note.title by_niceid))
      (Note.status_to_string (Note.status by_niceid)));
  [%expect {|
    get title=Hello content=World status=active
    get_by_niceid title=Hello status=active
    |}]

let%expect_test "update changes persisted fields" =
  with_note_repo (fun db note_repo ->
    let note = unwrap_note (NoteRepo.create note_repo
      ~title:(Title.make "Hello") ~content:(Content.make "World") ()) in
    let modified = Note.make (Note.id note) (Note.niceid note)
      (Title.make "Updated") (Content.make "Body")
      Note.Archived ~created_at:(Timestamp.make 0) ~updated_at:(Timestamp.make 0) in
    let updated = unwrap_note (NoteRepo.update note_repo modified) in
    Printf.printf "title=%s content=%s status=%s\n"
      (Title.to_string (Note.title updated))
      (Content.to_string (Note.content updated))
      (Note.status_to_string (Note.status updated));
    query_rows db "SELECT niceid, title, content, status FROM note" []);
  [%expect {|
    title=Updated content=Body status=archived
    nt-0|Updated|Body|archived
    |}]

let%expect_test "delete removes note and get_by_niceid returns Not_found" =
  with_note_repo (fun db note_repo ->
    let note = unwrap_note (NoteRepo.create note_repo
      ~title:(Title.make "Hello") ~content:(Content.make "World") ()) in
    let () = unwrap_note (NoteRepo.delete note_repo (Note.niceid note)) in
    (match NoteRepo.get_by_niceid note_repo (Note.niceid note) with
     | Error (NoteRepo.Not_found (`Niceid _)) -> print_endline "deleted ok"
     | Ok _ -> print_endline "unexpected: still exists"
     | Error err -> pp_error err);
    query_count db "note");
  [%expect {|
    deleted ok
    note=0
    |}]

let%expect_test "note repo not found cases" =
  with_note_repo (fun _db note_repo ->
    let missing_id = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in
    (match NoteRepo.get note_repo missing_id with
     | Error (NoteRepo.Not_found (`Id _)) -> print_endline "missing by id"
     | Ok _ -> print_endline "unexpected: found"
     | Error err -> pp_error err);
    let missing_niceid = Identifier.make "nt" 42 in
    (match NoteRepo.delete note_repo missing_niceid with
     | Error (NoteRepo.Not_found (`Niceid _)) -> print_endline "missing delete"
     | Ok () -> print_endline "unexpected: deleted"
     | Error err -> pp_error err));
  [%expect {|
    missing by id
    missing delete
    |}]

let%expect_test "note repo create with explicit status" =
  with_note_repo (fun db note_repo ->
    ignore (unwrap_note (NoteRepo.create note_repo
      ~title:(Title.make "Hello") ~content:(Content.make "World")
      ~status:Note.Archived ()));
    query_rows db "SELECT niceid, status FROM note" []);
  [%expect {|
    nt-0|archived
    |}]

let%expect_test "note repo list filters by status" =
  with_note_repo (fun _db note_repo ->
    ignore (unwrap_note (NoteRepo.create note_repo
      ~title:(Title.make "Active note") ~content:(Content.make "Body") ()));
    ignore (unwrap_note (NoteRepo.create note_repo
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
    print "all" [Note.Active; Note.Archived]);
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
  with_note_repo (fun _db note_repo ->
    ignore (unwrap_note (NoteRepo.create note_repo
      ~title:(Title.make "Active note") ~content:(Content.make "Body") ()));
    ignore (unwrap_note (NoteRepo.create note_repo
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
     | Error _ -> print_endline "list_all error"));
  [%expect {|
    list_all count=2
    nt-0 active
    nt-1 archived
    |}]

let%expect_test "note repo delete_all removes everything" =
  with_note_repo (fun db note_repo ->
    ignore (unwrap_note (NoteRepo.create note_repo
      ~title:(Title.make "First") ~content:(Content.make "Body") ()));
    ignore (unwrap_note (NoteRepo.create note_repo
      ~title:(Title.make "Second") ~content:(Content.make "Body") ()));

    let () = unwrap_note (NoteRepo.delete_all note_repo) in
    query_count db "note");
  [%expect {|
    note=0
    |}]

let%expect_test "note repo list empty table" =
  with_note_repo (fun _db note_repo ->
    (match NoteRepo.list note_repo ~statuses:[] with
     | Ok notes -> Printf.printf "count=%d\n" (List.length notes)
     | Error _ -> print_endline "unexpected error"));
  [%expect {|
    count=0
    |}]

let%expect_test "note repo import with caller-provided TypeId" =
  with_note_repo (fun db note_repo ->
    let tid = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in

    let note = unwrap_note (NoteRepo.import note_repo
      ~id:tid ~title:(Title.make "Imported") ~content:(Content.make "Body")
      ~status:Note.Archived ~created_at:(Timestamp.make 1000) ~updated_at:(Timestamp.make 2000) ()) in
    Printf.printf "id=%s niceid=%s status=%s\n"
      (Typeid.to_string (Note.id note))
      (Identifier.to_string (Note.niceid note))
      (Note.status_to_string (Note.status note));
    query_rows db "SELECT niceid, title, status FROM note" []);
  [%expect {|
    id=note_0123456789abcdefghjkmnpqrs niceid=nt-0 status=archived
    nt-0|Imported|archived
    |}]

let%expect_test "note repo import defaults to Active status" =
  with_note_repo (fun db note_repo ->
    let tid = Typeid.of_string "note_0123456789abcdefghjkmnpqrs" in

    ignore (unwrap_note (NoteRepo.import note_repo
      ~id:tid ~title:(Title.make "Default") ~content:(Content.make "Body")
      ~created_at:(Timestamp.make 1000) ~updated_at:(Timestamp.make 2000) ()));
    query_rows db "SELECT niceid, status FROM note" []);
  [%expect {|
    nt-0|active
    |}]
