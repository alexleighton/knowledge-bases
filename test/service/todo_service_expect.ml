module Root = Kbases.Repository.Root
module TodoService = Kbases.Service.Todo_service
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content

let query_count = Test_helpers.query_count
let query_rows = Test_helpers.query_rows

let unwrap = function
  | Ok v -> v
  | Error (TodoService.Repository_error msg) -> failwith ("repository error: " ^ msg)
  | Error (TodoService.Validation_error msg) -> failwith ("validation error: " ^ msg)

let with_todo_service f =
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = TodoService.init root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f root service)

let%expect_test "add persists a todo row" =
  with_todo_service (fun root svc ->
    ignore (unwrap (TodoService.add svc
      ~title:(Title.make "Fix bug")
      ~content:(Content.make "Details") ()));
    query_count root "todo";
    query_rows root "SELECT niceid, title, content, status FROM todo" [];
    query_count root "niceid");
  [%expect {|
    todo=1
    kb-0|Fix bug|Details|open
    niceid=1
  |}]

let%expect_test "add accepts explicit status" =
  with_todo_service (fun root svc ->
    ignore (unwrap (TodoService.add svc
      ~title:(Title.make "Ship")
      ~content:(Content.make "Soon")
      ~status:Todo.In_Progress ()));
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {| kb-0|in-progress |}]
