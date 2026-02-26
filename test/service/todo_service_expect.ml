module Root = Kbases.Repository.Root
module TodoService = Kbases.Service.Todo_service
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier

let with_todo_service f =
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = TodoService.init root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f service)

let pp_error = function
  | TodoService.Repository_error msg -> Printf.printf "repository error: %s\n" msg

let%expect_test "add returns a todo on success" =
  (match with_todo_service (fun svc ->
     TodoService.add svc
       ~title:(Title.make "Fix bug")
       ~content:(Content.make "Details")
       ()) with
   | Ok todo ->
       Printf.printf
         "niceid=%s title=%s content=%s status=%s\n"
         (Identifier.to_string (Todo.niceid todo))
         (Title.to_string (Todo.title todo))
         (Content.to_string (Todo.content todo))
         (Todo.status_to_string (Todo.status todo))
   | Error err -> pp_error err);
  [%expect {| niceid=kb-0 title=Fix bug content=Details status=open |}]

let%expect_test "add accepts explicit status" =
  (match with_todo_service (fun svc ->
     TodoService.add svc
       ~title:(Title.make "Ship")
       ~content:(Content.make "Soon")
       ~status:Todo.In_Progress
       ()) with
   | Ok todo ->
       Printf.printf "status=%s\n" (Todo.status_to_string (Todo.status todo))
   | Error err -> pp_error err);
  [%expect {| status=in-progress |}]
