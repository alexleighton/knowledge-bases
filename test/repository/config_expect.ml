module Config = Kbases.Repository.Config


let init_config db =
  match Config.init ~db with
  | Ok repo -> repo
  | Error (Config.Backend_failure msg) -> failwith ("init failed: " ^ msg)
  | Error (Config.Not_found key) -> failwith ("unexpected not found: " ^ key)

let pp_error = function
  | Config.Backend_failure msg -> Printf.printf "backend failure: %s\n" msg
  | Config.Not_found key -> Printf.printf "not found: %s\n" key

let expect_ok_unit = function
  | Ok () -> ()
  | Error (Config.Backend_failure msg) -> failwith ("backend failure: " ^ msg)
  | Error (Config.Not_found key) -> failwith ("unexpected not found: " ^ key)

let%expect_test "set persists value, get retrieves it, update overwrites, delete removes" =
  Test_helpers.with_db (fun db ->
    let repo = init_config db in
    expect_ok_unit (Config.set repo "namespace" "kb");
    (match Config.get repo "namespace" with
     | Ok value -> Printf.printf "namespace=%s\n" value
     | Error _ -> failwith "expected namespace")
    ;
    expect_ok_unit (Config.set repo "namespace" "kb2");
    (match Config.get repo "namespace" with
     | Ok value -> Printf.printf "namespace=%s\n" value
     | Error _ -> failwith "expected namespace update")
    ;
    (match Config.delete repo "namespace" with
     | Ok () -> print_endline "deleted"
     | Error _ -> failwith "expected delete success"));
  [%expect {|
    namespace=kb
    namespace=kb2
    deleted
    |}]

let%expect_test "config repo missing key paths" =
  Test_helpers.with_db (fun db ->
    let repo = init_config db in
    (match Config.get repo "missing" with
     | Error (Config.Not_found key) -> Printf.printf "missing get %s\n" key
     | Ok _ -> print_endline "unexpected: found"
     | Error err -> pp_error err);
    (match Config.delete repo "missing" with
     | Error (Config.Not_found key) -> Printf.printf "missing delete %s\n" key
     | Ok () -> print_endline "unexpected: deleted"
     | Error err -> pp_error err));
  [%expect {|
    missing get missing
    missing delete missing
    |}]
