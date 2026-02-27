module TodoRepo = Kbases.Repository.Todo
module Niceid = Kbases.Repository.Niceid
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid

let _unwrap_todo = function
  | Ok v -> v
  | Error _ -> failwith "unexpected error"

let _unwrap_niceid = function
  | Ok v -> v
  | Error (Niceid.Backend_failure msg) -> failwith ("backend failure: " ^ msg)

let%expect_test "todo repo create/get/update/delete happy path" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"td") in
  let todo_repo = _unwrap_todo (TodoRepo.init ~db ~niceid_repo) in

  let todo1 = _unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "Hello") ~content:(Content.make "World") ()) in
  Printf.printf "created niceid=%s status=%s\n"
    (Identifier.to_string (Todo.niceid todo1))
    (Todo.status_to_string (Todo.status todo1));

  let fetched = _unwrap_todo (TodoRepo.get todo_repo (Todo.id todo1)) in
  Printf.printf "fetched title=%s content=%s status=%s\n"
    (Title.to_string (Todo.title fetched))
    (Content.to_string (Todo.content fetched))
    (Todo.status_to_string (Todo.status fetched));

  let fetched_by_niceid = _unwrap_todo (TodoRepo.get_by_niceid todo_repo (Todo.niceid todo1)) in
  Printf.printf "fetched_by_niceid title=%s\n" (Title.to_string (Todo.title fetched_by_niceid));

  let updated =
    Todo.make
      (Todo.id todo1)
      (Todo.niceid todo1)
      (Title.make "Updated")
      (Content.make "Body")
      Todo.Done
  in
  let updated = _unwrap_todo (TodoRepo.update todo_repo updated) in
  Printf.printf "updated title=%s content=%s status=%s\n"
    (Title.to_string (Todo.title updated))
    (Content.to_string (Todo.content updated))
    (Todo.status_to_string (Todo.status updated));

  let () = _unwrap_todo (TodoRepo.delete todo_repo (Todo.niceid todo1)) in
  (match TodoRepo.get_by_niceid todo_repo (Todo.niceid todo1) with
   | Error (TodoRepo.Not_found (`Niceid _)) -> print_endline "deleted ok"
   | Ok _ -> print_endline "unexpected lookup result"
   | Error (TodoRepo.Duplicate_niceid _) -> print_endline "unexpected duplicate"
   | Error (TodoRepo.Backend_failure _) -> print_endline "backend failure"
   | Error (TodoRepo.Not_found (`Id _)) -> print_endline "unexpected not found id");

  ignore (Sqlite3.db_close db);
  [%expect {|
    created niceid=td-0 status=open
    fetched title=Hello content=World status=open
    fetched_by_niceid title=Hello
    updated title=Updated content=Body status=done
    deleted ok
    |}]

let%expect_test "todo repo create with explicit status" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"td") in
  let todo_repo = _unwrap_todo (TodoRepo.init ~db ~niceid_repo) in

  let todo1 = _unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "Hello") ~content:(Content.make "World")
    ~status:Todo.In_Progress ()) in
  Printf.printf "created status=%s\n" (Todo.status_to_string (Todo.status todo1));

  ignore (Sqlite3.db_close db);
  [%expect {|
    created status=in-progress
    |}]

let%expect_test "todo repo not found cases" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"td") in
  let todo_repo = _unwrap_todo (TodoRepo.init ~db ~niceid_repo) in
  let missing_id = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs" in
  (match TodoRepo.get todo_repo missing_id with
   | Error (TodoRepo.Not_found (`Id _)) -> print_endline "missing by id"
   | Ok _ -> print_endline "unexpected get result"
   | Error (TodoRepo.Not_found (`Niceid _)) -> print_endline "unexpected not found niceid"
   | Error (TodoRepo.Duplicate_niceid _) -> print_endline "unexpected duplicate"
   | Error (TodoRepo.Backend_failure _) -> print_endline "backend failure");
  let missing_niceid = Identifier.make "td" 42 in
  (match TodoRepo.delete todo_repo missing_niceid with
   | Error (TodoRepo.Not_found (`Niceid _)) -> print_endline "missing delete"
   | Ok () -> print_endline "unexpected delete result"
   | Error (TodoRepo.Not_found (`Id _)) -> print_endline "unexpected not found id"
   | Error (TodoRepo.Duplicate_niceid _) -> print_endline "unexpected duplicate"
   | Error (TodoRepo.Backend_failure _) -> print_endline "backend failure");
  ignore (Sqlite3.db_close db);
  [%expect {|
    missing by id
    missing delete
    |}]

let%expect_test "todo repo list filters by status" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"td") in
  let todo_repo = _unwrap_todo (TodoRepo.init ~db ~niceid_repo) in

  ignore (_unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "Open work") ~content:(Content.make "Body") ()));
  ignore (_unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "In progress") ~content:(Content.make "Body")
    ~status:Todo.In_Progress ()));
  ignore (_unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "Done item") ~content:(Content.make "Body")
    ~status:Todo.Done ()));

  let print label statuses =
    match TodoRepo.list todo_repo ~statuses with
    | Ok todos ->
        Printf.printf "%s:\n" label;
        List.iter (fun todo ->
          Printf.printf "%s %s\n"
            (Identifier.to_string (Todo.niceid todo))
            (Todo.status_to_string (Todo.status todo))
        ) todos
    | Error _ -> print_endline "list error"
  in

  print "default" [];
  print "open-only" [Todo.Open];
  print "done-only" [Todo.Done];
  print "open+in-progress" [Todo.Open; Todo.In_Progress];

  ignore (Sqlite3.db_close db);
  [%expect {|
    default:
    td-0 open
    td-1 in-progress
    open-only:
    td-0 open
    done-only:
    td-2 done
    open+in-progress:
    td-0 open
    td-1 in-progress
    |}]

let%expect_test "todo repo list_all returns all statuses" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"td") in
  let todo_repo = _unwrap_todo (TodoRepo.init ~db ~niceid_repo) in

  ignore (_unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "Open work") ~content:(Content.make "Body") ()));
  ignore (_unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "In progress") ~content:(Content.make "Body")
    ~status:Todo.In_Progress ()));
  ignore (_unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "Done item") ~content:(Content.make "Body")
    ~status:Todo.Done ()));

  (match TodoRepo.list_all todo_repo with
   | Ok todos ->
       Printf.printf "list_all count=%d\n" (List.length todos);
       let sorted = List.sort (fun a b ->
         compare (Identifier.raw_id (Todo.niceid a)) (Identifier.raw_id (Todo.niceid b))
       ) todos in
       List.iter (fun todo ->
         Printf.printf "%s %s\n"
           (Identifier.to_string (Todo.niceid todo))
           (Todo.status_to_string (Todo.status todo))
       ) sorted
   | Error _ -> print_endline "list_all error");

  ignore (Sqlite3.db_close db);
  [%expect {|
    list_all count=3
    td-0 open
    td-1 in-progress
    td-2 done
    |}]

let%expect_test "todo repo delete_all removes everything" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"td") in
  let todo_repo = _unwrap_todo (TodoRepo.init ~db ~niceid_repo) in

  ignore (_unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "First") ~content:(Content.make "Body") ()));
  ignore (_unwrap_todo (TodoRepo.create todo_repo
    ~title:(Title.make "Second") ~content:(Content.make "Body") ()));

  let () = _unwrap_todo (TodoRepo.delete_all todo_repo) in
  (match TodoRepo.list_all todo_repo with
   | Ok todos -> Printf.printf "after delete_all count=%d\n" (List.length todos)
   | Error _ -> print_endline "list_all error");

  ignore (Sqlite3.db_close db);
  [%expect {|
    after delete_all count=0
    |}]

let%expect_test "todo repo list empty table" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"td") in
  let todo_repo = _unwrap_todo (TodoRepo.init ~db ~niceid_repo) in
  (match TodoRepo.list todo_repo ~statuses:[] with
   | Ok todos -> Printf.printf "count=%d\n" (List.length todos)
   | Error _ -> print_endline "unexpected error");
  ignore (Sqlite3.db_close db);
  [%expect {|
    count=0
    |}]

let%expect_test "todo repo import with caller-provided TypeId" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"td") in
  let todo_repo = _unwrap_todo (TodoRepo.init ~db ~niceid_repo) in
  let tid = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs" in

  let todo = _unwrap_todo (TodoRepo.import todo_repo
    ~id:tid ~title:(Title.make "Imported") ~content:(Content.make "Body")
    ~status:Todo.In_Progress ()) in
  Printf.printf "id=%s niceid=%s status=%s\n"
    (Typeid.to_string (Todo.id todo))
    (Identifier.to_string (Todo.niceid todo))
    (Todo.status_to_string (Todo.status todo));

  let fetched = _unwrap_todo (TodoRepo.get todo_repo tid) in
  Printf.printf "fetched title=%s\n" (Title.to_string (Todo.title fetched));

  ignore (Sqlite3.db_close db);
  [%expect {|
    id=todo_0123456789abcdefghjkmnpqrs niceid=td-0 status=in-progress
    fetched title=Imported
    |}]

let%expect_test "todo repo import defaults to Open status" =
  let db = Sqlite3.db_open ":memory:" in
  let niceid_repo = _unwrap_niceid (Niceid.init ~db ~namespace:"td") in
  let todo_repo = _unwrap_todo (TodoRepo.init ~db ~niceid_repo) in
  let tid = Typeid.of_string "todo_0123456789abcdefghjkmnpqrs" in

  let todo = _unwrap_todo (TodoRepo.import todo_repo
    ~id:tid ~title:(Title.make "Default") ~content:(Content.make "Body") ()) in
  Printf.printf "status=%s\n" (Todo.status_to_string (Todo.status todo));

  ignore (Sqlite3.db_close db);
  [%expect {|
    status=open
    |}]
