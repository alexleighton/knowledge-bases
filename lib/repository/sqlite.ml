module Sql = Sqlite3

(* Suppress fragile-match: Sqlite3.Rc.t has ~30 constructors; catch-all
   arms are the correct pattern for this wrapper module. *)
[@@@warning "-4"]

type error =
  | Step_failed of string
  | Constraint_violation
  | Bind_failed of string
  | Row_parse_failed of string
  | No_row_found

let error_message = function
  | Step_failed msg | Bind_failed msg | Row_parse_failed msg -> msg
  | Constraint_violation -> "constraint violation"
  | No_row_found -> "no row found"

let _step_failed rc =
  Step_failed (Printf.sprintf "sqlite step failed: %s" (Sql.Rc.to_string rc))

let exec db sql =
  match Sql.exec db sql with
  | Sql.Rc.OK -> Ok ()
  | rc -> Error (Printf.sprintf "sqlite exec failed: %s" (Sql.Rc.to_string rc))

let commit db = exec db "COMMIT"

let rollback db = exec db "ROLLBACK"

let _finalize stmt =
  match Sql.finalize stmt with
  | Sql.Rc.OK -> ()
  | _ -> ()

let _bind_params stmt params =
  let rec bind_all = function
    | [] -> Ok ()
    | (idx, data) :: rest ->
        match Sql.bind stmt idx data with
        | Sql.Rc.OK -> bind_all rest
        | rc -> Error (Bind_failed (Printf.sprintf "sqlite bind failed: %s" (Sql.Rc.to_string rc)))
  in
  bind_all params

let _with_prepared db sql params f =
  try
    let stmt = Sql.prepare db sql in
    Fun.protect ~finally:(fun () -> _finalize stmt) (fun () ->
      match _bind_params stmt params with
      | Error _ as e -> e
      | Ok () -> f stmt)
  with
  | Sql.Error msg -> Error (Row_parse_failed msg)
  | Invalid_argument msg -> Error (Row_parse_failed msg)

let with_stmt db sql params row_fn =
  let rec collect_rows stmt acc =
    match Sql.step stmt with
    | Sql.Rc.ROW ->
        (match row_fn stmt with
         | Ok row -> collect_rows stmt (row :: acc)
         | Error _ as e -> e)
    | Sql.Rc.DONE -> Ok (List.rev acc)
    | Sql.Rc.CONSTRAINT -> Error Constraint_violation
    | rc -> Error (_step_failed rc)
  in
  _with_prepared db sql params (fun stmt -> collect_rows stmt [])

let with_stmt_single db sql params row_fn =
  _with_prepared db sql params (fun stmt ->
    match Sql.step stmt with
    | Sql.Rc.ROW -> row_fn stmt
    | Sql.Rc.DONE -> Error No_row_found
    | Sql.Rc.CONSTRAINT -> Error Constraint_violation
    | rc -> Error (_step_failed rc))

let with_stmt_cmd db sql params =
  _with_prepared db sql params (fun stmt ->
    match Sql.step stmt with
    | Sql.Rc.DONE -> Ok ()
    | Sql.Rc.CONSTRAINT -> Error Constraint_violation
    | rc -> Error (_step_failed rc))
