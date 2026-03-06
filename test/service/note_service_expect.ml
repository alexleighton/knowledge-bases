module Root = Kbases.Repository.Root
module NoteService = Kbases.Service.Note_service
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content

let query_count = Test_helpers.query_count
let query_rows = Test_helpers.query_rows

let unwrap = function
  | Ok v -> v
  | Error (NoteService.Repository_error msg) -> failwith ("repository error: " ^ msg)

let with_note_service f =
  Test_helpers.with_service NoteService.init f

let%expect_test "add persists a note row" =
  with_note_service (fun root svc ->
    ignore (unwrap (NoteService.add svc
      ~title:(Title.make "Reminder")
      ~content:(Content.make "Pay bills")));
    query_count root "note";
    query_rows root "SELECT niceid, title, content, status FROM note" [];
    query_count root "niceid");
  [%expect {|
    note=1
    kb-0|Reminder|Pay bills|active
    niceid=1
  |}]
