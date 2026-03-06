module Config = Kbases.Repository.Config

let with_db = Test_helpers.with_db

let init_config db =
  match Config.init ~db with
  | Ok repo -> repo
  | Error (Config.Backend_failure msg) -> failwith ("init failed: " ^ msg)
  | Error (Config.Not_found key) -> failwith ("unexpected not found: " ^ key)

let expect_ok_unit = function
  | Ok () -> ()
  | Error (Config.Backend_failure msg) -> failwith ("backend failure: " ^ msg)
  | Error (Config.Not_found key) -> failwith ("unexpected not found: " ^ key)

let%expect_test "config repo set/get/update/delete happy path" =
  with_db (fun db ->
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
  with_db (fun db ->
    let repo = init_config db in
    (match Config.get repo "missing" with
     | Error (Config.Not_found key) -> Printf.printf "missing get %s\n" key
     | Ok _ -> failwith "expected missing get"
     | Error (Config.Backend_failure msg) -> failwith ("backend failure: " ^ msg));
    (match Config.delete repo "missing" with
     | Error (Config.Not_found key) -> Printf.printf "missing delete %s\n" key
     | Ok () -> failwith "expected missing delete"
     | Error (Config.Backend_failure msg) -> failwith ("backend failure: " ^ msg)));
  [%expect {|
    missing get missing
    missing delete missing
    |}]
