module Sqlite = Kbases.Repository.Sqlite

let _print_exec_result label = function
  | Ok () -> Printf.printf "%s ok\n" label
  | Error msg -> Printf.printf "%s err: %s\n" label msg

let _print_error = function
  | Sqlite.Constraint_violation -> print_endline "constraint_violation"
  | Sqlite.No_row_found -> print_endline "no_row_found"
  | Sqlite.Step_failed msg -> Printf.printf "step_failed: %s\n" msg
  | Sqlite.Bind_failed msg -> Printf.printf "bind_failed: %s\n" msg
  | Sqlite.Row_parse_failed msg -> Printf.printf "row_parse_failed: %s\n" msg

let%expect_test "exec commit rollback" =
  let db = Sqlite3.db_open ":memory:" in
  _print_exec_result "create" (Sqlite.exec db "CREATE TABLE items(id INTEGER)");
  _print_exec_result "bad_sql" (Sqlite.exec db "THIS IS BAD SQL");
  _print_exec_result "begin" (Sqlite.exec db "BEGIN");
  _print_exec_result "insert" (Sqlite.exec db "INSERT INTO items(id) VALUES (1)");
  _print_exec_result "commit" (Sqlite.commit db);
  let count_after_commit =
    Sqlite.with_stmt_single db "SELECT COUNT(*) FROM items" [] (fun stmt ->
      Ok (Sqlite3.column_int stmt 0))
  in
  (match count_after_commit with
   | Ok c -> Printf.printf "count after commit=%d\n" c
   | Error e -> _print_error e);
  _print_exec_result "begin2" (Sqlite.exec db "BEGIN");
  _print_exec_result "insert2" (Sqlite.exec db "INSERT INTO items(id) VALUES (2)");
  _print_exec_result "rollback" (Sqlite.rollback db);
  let count_after_rollback =
    Sqlite.with_stmt_single db "SELECT COUNT(*) FROM items" [] (fun stmt ->
      Ok (Sqlite3.column_int stmt 0))
  in
  (match count_after_rollback with
   | Ok c -> Printf.printf "count after rollback=%d\n" c
   | Error e -> _print_error e);
  ignore (Sqlite3.db_close db);
  [%expect {|
    create ok
    bad_sql err: sqlite exec failed: ERROR
    begin ok
    insert ok
    commit ok
    count after commit=1
    begin2 ok
    insert2 ok
    rollback ok
    count after rollback=1
    |}]

let%expect_test "with_stmt collects rows" =
  let db = Sqlite3.db_open ":memory:" in
  ignore (Sqlite.exec db "CREATE TABLE numbers(n INTEGER, label TEXT)");
  ignore (Sqlite.exec db "INSERT INTO numbers(n, label) VALUES (1, 'one'), (2, 'two'), (3, 'three')");
  let rows =
    Sqlite.with_stmt db
      "SELECT n, label FROM numbers WHERE n >= ? ORDER BY n"
      [ (1, Sqlite3.Data.INT 2L) ]
      (fun stmt ->
         let n = Sqlite3.column_int stmt 0 in
         let label = Sqlite3.column_text stmt 1 in
         Ok (Printf.sprintf "%d:%s" n label))
  in
  (match rows with
   | Ok rows -> Printf.printf "rows=%s\n" (String.concat "; " rows)
   | Error e -> _print_error e);
  ignore (Sqlite3.db_close db);
  [%expect {|
    rows=2:two; 3:three
    |}]

let%expect_test "with_stmt_single ok and missing" =
  let db = Sqlite3.db_open ":memory:" in
  ignore (Sqlite.exec db "CREATE TABLE numbers(n INTEGER)");
  ignore (Sqlite.exec db "INSERT INTO numbers(n) VALUES (5)");
  let found =
    Sqlite.with_stmt_single db "SELECT n FROM numbers WHERE n = ?" [ (1, Sqlite3.Data.INT 5L) ]
      (fun stmt -> Ok (Sqlite3.column_int stmt 0))
  in
  (match found with
   | Ok n -> Printf.printf "found=%d\n" n
   | Error e -> _print_error e);
  let missing =
    Sqlite.with_stmt_single db "SELECT n FROM numbers WHERE n = ?" [ (1, Sqlite3.Data.INT 9L) ]
      (fun stmt -> Ok (Sqlite3.column_int stmt 0))
  in
  (match missing with
   | Ok n -> Printf.printf "missing=%d\n" n
   | Error e -> _print_error e);
  ignore (Sqlite3.db_close db);
  [%expect {|
    found=5
    no_row_found
    |}]

let%expect_test "with_stmt_cmd constraint violation" =
  let db = Sqlite3.db_open ":memory:" in
  ignore (Sqlite.exec db "CREATE TABLE uniq(v TEXT UNIQUE)");
  (match Sqlite.with_stmt_cmd db "INSERT INTO uniq(v) VALUES (?)" [ (1, Sqlite3.Data.TEXT "a") ] with
   | Ok () -> print_endline "first insert ok"
   | Error e -> _print_error e);
  (match Sqlite.with_stmt_cmd db "INSERT INTO uniq(v) VALUES (?)" [ (1, Sqlite3.Data.TEXT "a") ] with
   | Ok () -> print_endline "second insert ok"
   | Error e -> _print_error e);
  ignore (Sqlite3.db_close db);
  [%expect {|
    first insert ok
    constraint_violation
    |}]
