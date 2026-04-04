module Root = Kbases.Repository.Root
module Config = Kbases.Repository.Config
module ConfigService = Kbases.Service.Config_service

open Test_helpers

let pp_error = pp_config_error

(* --- validation tests --- *)

let%expect_test "namespace validation accepts valid namespace" =
  with_config_service (fun root service ->
    ignore (Config.set (Root.config root) "namespace" "kb" : (unit, Config.error) result);
    ignore (Config.set (Root.config root) "mode" "local" : (unit, Config.error) result);
    match ConfigService.set service "namespace" "proj" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| ok |}]

let%expect_test "namespace validation rejects uppercase" =
  with_config_service (fun root service ->
    ignore (Config.set (Root.config root) "namespace" "kb" : (unit, Config.error) result);
    match ConfigService.set service "namespace" "PROJ" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| validation error: namespace must match `^[a-z]+$`, got "PROJ" |}]

let%expect_test "gc_max_age validation accepts integer seconds" =
  with_config_service (fun _root service ->
    match ConfigService.set service "gc_max_age" "604800" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| ok |}]

let%expect_test "gc_max_age validation rejects non-integer" =
  with_config_service (fun _root service ->
    match ConfigService.set service "gc_max_age" "banana" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| validation error: invalid gc_max_age: "banana" (expected integer seconds) |}]

let%expect_test "gc_max_age validation rejects day shorthand" =
  with_config_service (fun _root service ->
    match ConfigService.set service "gc_max_age" "7d" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| validation error: invalid gc_max_age: "7d" (expected integer seconds) |}]

let%expect_test "mode validation accepts local" =
  with_config_service (fun _root service ->
    match ConfigService.set service "mode" "local" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| ok |}]

let%expect_test "mode validation rejects invalid value" =
  with_config_service (fun _root service ->
    match ConfigService.set service "mode" "banana" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| validation error: invalid mode: "banana" (expected "local" or "shared") |}]

(* --- no-op detection tests --- *)

let%expect_test "set gc_max_age to default when never set returns Nothing_to_update" =
  with_config_service (fun _root service ->
    match ConfigService.set service "gc_max_age" "2592000" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| nothing to update |}]

let%expect_test "set namespace to current value returns Nothing_to_update" =
  with_config_service (fun root service ->
    ignore (Config.set (Root.config root) "namespace" "kb" : (unit, Config.error) result);
    match ConfigService.set service "namespace" "kb" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| nothing to update |}]

let%expect_test "set mode to default when never set returns Nothing_to_update" =
  with_config_service (fun _root service ->
    match ConfigService.set service "mode" "shared" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| nothing to update |}]

(* --- set persists value tests --- *)

let%expect_test "set gc_max_age persists the value in DB" =
  with_config_service (fun root service ->
    (match ConfigService.set service "gc_max_age" "604800" with
     | Ok () -> ()
     | Error e -> pp_error e);
    query_db root
      "SELECT value FROM config WHERE key = 'gc_max_age'"
      []
      (fun stmt -> Sqlite3.column_text stmt 0));
  [%expect {| 604800 |}]

let%expect_test "set mode persists the value in DB" =
  with_config_service (fun root service ->
    (match ConfigService.set service "mode" "local" with
     | Ok () -> ()
     | Error e -> pp_error e);
    query_db root
      "SELECT value FROM config WHERE key = 'mode'"
      []
      (fun stmt -> Sqlite3.column_text stmt 0));
  [%expect {| local |}]

(* --- namespace rename side effects --- *)

module TodoRepo = Kbases.Repository.Todo
module NoteRepo = Kbases.Repository.Note
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content

let%expect_test "set namespace renames niceids in niceid, todo, and note tables" =
  with_config_service (fun root service ->
    ignore (Config.set (Root.config root) "namespace" "kb" : (unit, Config.error) result);
    ignore (Config.set (Root.config root) "mode" "local" : (unit, Config.error) result);
    ignore (unwrap_todo_repo
      (TodoRepo.create (Root.todo root)
        ~title:(Title.make "A todo") ~content:(Content.make "body") ()));
    ignore (unwrap_note_repo
      (NoteRepo.create (Root.note root)
        ~title:(Title.make "A note") ~content:(Content.make "body") ()));
    (match ConfigService.set service "namespace" "proj" with
     | Ok () -> Printf.printf "ok\n"
     | Error e -> pp_error e);
    Printf.printf "--- niceid table ---\n";
    query_rows root "SELECT namespace, niceid FROM niceid ORDER BY niceid" [];
    Printf.printf "--- todo table ---\n";
    query_db root "SELECT niceid FROM todo" []
      (fun stmt -> Sqlite3.column_text stmt 0);
    Printf.printf "--- note table ---\n";
    query_db root "SELECT niceid FROM note" []
      (fun stmt -> Sqlite3.column_text stmt 0));
  [%expect {|
    ok
    --- niceid table ---
    proj|0
    proj|1
    --- todo table ---
    proj-0
    --- note table ---
    proj-1
  |}]

let%expect_test "set namespace to uppercase returns Validation_error" =
  with_config_service (fun root service ->
    ignore (Config.set (Root.config root) "namespace" "kb" : (unit, Config.error) result);
    match ConfigService.set service "namespace" "UPPER" with
    | Ok () -> Printf.printf "ok\n"
    | Error e -> pp_error e);
  [%expect {| validation error: namespace must match `^[a-z]+$`, got "UPPER" |}]
