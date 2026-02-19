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
