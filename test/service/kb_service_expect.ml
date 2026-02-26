module Root = Kbases.Repository.Root
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier

let create_git_root = Test_helpers.create_git_root
let with_chdir = Test_helpers.with_chdir

let pp_error err =
  match err with
  | Service.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | Service.Validation_error msg -> Printf.printf "validation error: %s\n" msg

let expect_ok result f =
  match result with
  | Error err -> pp_error err
  | Ok v -> f v

let with_open_kb f =
  expect_ok (Service.open_kb ()) (fun (root, service) ->
    Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f service))

let%expect_test "open_kb succeeds and returns functional service" =
  let root = create_git_root "kb-open-happy-" in
  with_chdir root (fun () ->
    expect_ok
      (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb"))
      (fun _ ->
        with_open_kb (fun service ->
          expect_ok
            (Service.add_note service
               ~title:(Title.make "From open_kb")
               ~content:(Content.make "Works"))
            (fun note ->
              Printf.printf "niceid=%s title=%s\n"
                (Identifier.to_string (Note.niceid note))
                (Title.to_string (Note.title note))))));
  [%expect {| niceid=kb-0 title=From open_kb |}]
