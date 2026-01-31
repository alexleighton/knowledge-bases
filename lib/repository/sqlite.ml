module Sql = Sqlite3

type error =
  | Step_failed of string
  | Constraint_violation
  | Bind_failed of string
  | Row_parse_failed of string
  | No_row_found

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

(* Prepare, bind, and delegate to [f], which must call [finish] to finalize *)
let _with_prepared db sql params f =
  try
    let stmt = Sql.prepare db sql in
    match _bind_params stmt params with
    | Error _ as e ->
        _finalize stmt;
        e
    | Ok () ->
        f stmt (fun res ->
          _finalize stmt;
          res)
  with
  | Sql.Error msg -> Error (Row_parse_failed msg)
  | Invalid_argument msg -> Error (Row_parse_failed msg)

let with_stmt db sql params row_fn =
  let rec collect_rows stmt finish acc =
    match Sql.step stmt with
    | Sql.Rc.ROW ->
        (match row_fn stmt with
         | Ok row -> collect_rows stmt finish (row :: acc)
         | Error _ as e -> finish e)
    | Sql.Rc.DONE -> finish (Ok (List.rev acc))
    | Sql.Rc.CONSTRAINT -> finish (Error Constraint_violation)
    | rc -> finish (Error (_step_failed rc))
  in
  _with_prepared db sql params (fun stmt finish -> collect_rows stmt finish [])

let with_stmt_single db sql params row_fn =
  _with_prepared db sql params (fun stmt finish ->
    match Sql.step stmt with
    | Sql.Rc.ROW ->
        (match row_fn stmt with
         | Ok row -> finish (Ok row)
         | Error _ as e -> finish e)
    | Sql.Rc.DONE -> finish (Error No_row_found)
    | Sql.Rc.CONSTRAINT -> finish (Error Constraint_violation)
    | rc -> finish (Error (_step_failed rc)))

let with_stmt_cmd db sql params =
  _with_prepared db sql params (fun stmt finish ->
    match Sql.step stmt with
    | Sql.Rc.DONE -> finish (Ok ())
    | Sql.Rc.CONSTRAINT -> finish (Error Constraint_violation)
    | rc -> finish (Error (_step_failed rc)))
