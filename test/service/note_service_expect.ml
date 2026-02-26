module Root = Kbases.Repository.Root
module NoteService = Kbases.Service.Note_service
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier

let with_note_service f =
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = NoteService.init root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f service)

let pp_error = function
  | NoteService.Repository_error msg -> Printf.printf "repository error: %s\n" msg

let%expect_test "add returns a note on success" =
  (match with_note_service (fun svc ->
     NoteService.add svc
       ~title:(Title.make "Reminder")
       ~content:(Content.make "Pay bills")) with
   | Ok note ->
       Printf.printf
         "niceid=%s title=%s content=%s\n"
         (Identifier.to_string (Note.niceid note))
         (Title.to_string (Note.title note))
         (Content.to_string (Note.content note))
   | Error err -> pp_error err);
  [%expect {| niceid=kb-0 title=Reminder content=Pay bills |}]
