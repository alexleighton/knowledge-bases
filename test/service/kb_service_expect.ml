module Root = Kbases.Repository.Root
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Identifier = Kbases.Data.Identifier

let with_service f =
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = Service.init root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f service)

let pp_error err =
  match err with
  | Service.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | Service.Validation_error msg -> Printf.printf "validation error: %s\n" msg

let%expect_test "add_note returns a note on success" =
  (match with_service (fun svc -> Service.add_note svc ~title:"Reminder" ~content:"Pay bills") with
   | Ok note ->
       Printf.printf
         "niceid=%s title=%s content=%s\n"
         (Identifier.to_string (Note.niceid note))
         (Note.title note)
         (Note.content note)
   | Error err -> pp_error err);
  [%expect {| niceid=kb-0 title=Reminder content=Pay bills |}]

let%expect_test "add_note rejects empty title" =
  (match with_service (fun svc -> Service.add_note svc ~title:"" ~content:"Body") with
   | Ok _ -> Printf.printf "Expected validation to fail\n"
   | Error err -> pp_error err);
  [%expect
    {|
    validation error: title must be between 1 and 100 characters, got 0
    |}]

let%expect_test "add_note rejects empty content" =
  (match with_service (fun svc -> Service.add_note svc ~title:"Note" ~content:"") with
   | Ok _ -> Printf.printf "Expected validation to fail\n"
   | Error err -> pp_error err);
  [%expect
    {|
    validation error: content must be between 1 and 10000 characters, got 0
    |}]
