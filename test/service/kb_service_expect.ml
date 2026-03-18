module Root = Kbases.Repository.Root
module TodoRepo = Kbases.Repository.Todo
module Service = Kbases.Service.Kb_service
module Note = Kbases.Data.Note
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Relation_kind = Kbases.Data.Relation_kind

let with_git_root = Test_helpers.with_git_root
let with_chdir = Test_helpers.with_chdir
let query_count = Test_helpers.query_count
let query_rows = Test_helpers.query_rows

let pp_error = Test_helpers.pp_item_error

let expect_ok result f =
  match result with
  | Error err -> pp_error err
  | Ok v -> f v

let with_open_kb f =
  expect_ok (Service.open_kb ()) (fun (root, service) ->
    Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f root service))

let%expect_test "open_kb succeeds and returns functional service" =
  with_git_root "kb-open-happy-" (fun root ->
    with_chdir root (fun () ->
      expect_ok
        (Service.init_kb ~directory:(Some root) ~namespace:(Some "kb") ~gc_max_age:None)
        (fun _ ->
          with_open_kb (fun db_root service ->
            expect_ok
              (Service.add_note service
                 ~title:(Title.make "From open_kb")
                 ~content:(Content.make "Works"))
              (fun note ->
                Printf.printf "niceid=%s title=%s\n"
                  (Identifier.to_string (Note.niceid note))
                  (Title.to_string (Note.title note));
                query_count db_root "note";
                query_rows db_root "SELECT niceid, title, status FROM note" [];
                query_rows db_root "SELECT value FROM config WHERE key = 'namespace'" [])))));
  [%expect {|
    niceid=kb-0 title=From open_kb
    note=1
    kb-0|From open_kb|active
    kb
  |}]

let unwrap_todo_repo = Test_helpers.unwrap_todo_repo

let with_service f =
  Test_helpers.with_service Service.init f

let%expect_test "resolve via Kb_service" =
  with_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Fix bug") ~content:(Content.make "Details") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    (match Service.resolve service ~identifier:niceid_str with
     | Ok t ->
         Printf.printf "Resolved: %s status=%s\n"
           (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Error err -> pp_error err);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Resolved: kb-0 status=done
    kb-0|done
  |}]

let%expect_test "claim via Kb_service" =
  with_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    (match Service.claim service ~identifier:niceid_str with
     | Ok t ->
         Printf.printf "Claimed: %s status=%s\n"
           (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Error err ->
         let msg = match err with
           | Service.Not_a_todo id -> "not a todo: " ^ id
           | Service.Not_open { niceid; status } ->
               Printf.sprintf "not open: %s (%s)" niceid status
           | Service.Blocked { niceid; blocked_by } ->
               Printf.sprintf "blocked: %s by [%s]" niceid (String.concat "; " blocked_by)
           | Service.Nothing_available { stuck_count } ->
               Printf.sprintf "nothing available: %d stuck" stuck_count
           | Service.Service_error _ -> "service error"
         in
         Printf.printf "claim error: %s\n" msg);
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Claimed: kb-0 status=in-progress
    kb-0|in-progress
  |}]

let%expect_test "next via Kb_service" =
  with_service (fun root service ->
    ignore (unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()));
    (match Service.next service with
     | Ok (Some t) ->
         Printf.printf "Next: %s status=%s\n"
           (Identifier.to_string (Todo.niceid t))
           (Todo.status_to_string (Todo.status t))
     | Ok None -> print_endline "none"
     | Error _ -> print_endline "error");
    query_rows root "SELECT niceid, status FROM todo" []);
  [%expect {|
    Next: kb-0 status=in-progress
    kb-0|in-progress
  |}]

(* -- add_*_with_relations tests -- *)

let pp_add_result { Service.niceid; entity_type; relations; typeid = _ } =
  Printf.printf "niceid=%s entity_type=%s relations=%d\n"
    (Identifier.to_string niceid)
    entity_type
    (List.length relations);
  List.iter (fun (re : Service.relation_entry) ->
    Printf.printf "  rel: %s %s (%s)\n"
      (Relation_kind.to_string re.kind)
      (Identifier.to_string re.niceid)
      re.entity_type)
    relations

let%expect_test "add_note_with_relations creates note and relation" =
  with_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Target") ~content:(Content.make "Body") ()) in
    let specs = [Service.{
      target = Identifier.to_string (Todo.niceid todo);
      kind = "depends-on"; bidirectional = false; blocking = false }] in
    (match Service.add_note_with_relations service
             ~title:(Title.make "My Note") ~content:(Content.make "Body")
             ~specs with
     | Ok r -> pp_add_result r
     | Error err -> pp_error err);
    query_count root "note";
    query_count root "relation");
  [%expect {|
    niceid=kb-1 entity_type=note relations=1
      rel: depends-on kb-0 (todo)
    note=1
    relation=1
  |}]

let%expect_test "add_todo_with_relations creates todo and relation" =
  with_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Target") ~content:(Content.make "Body") ()) in
    let specs = [Service.{
      target = Identifier.to_string (Todo.niceid todo);
      kind = "related-to"; bidirectional = true; blocking = false }] in
    (match Service.add_todo_with_relations service
             ~title:(Title.make "My Todo") ~content:(Content.make "Body")
             ~specs () with
     | Ok r -> pp_add_result r
     | Error err -> pp_error err);
    query_count root "todo";
    query_count root "relation");
  [%expect {|
    niceid=kb-1 entity_type=todo relations=1
      rel: related-to kb-0 (todo)
    todo=2
    relation=1
  |}]

let%expect_test "add_note_with_relations with invalid target rolls back note" =
  with_service (fun root service ->
    let specs = [Service.{
      target = "kb-999"; kind = "depends-on"; bidirectional = false; blocking = false }] in
    (match Service.add_note_with_relations service
             ~title:(Title.make "My Note") ~content:(Content.make "Body")
             ~specs with
     | Ok _ -> print_endline "unexpected success"
     | Error err -> pp_error err);
    query_count root "note");
  [%expect {|
    validation error: item not found: kb-999
    note=0
  |}]

let%expect_test "add_note_with_relations with invalid second spec rolls back both" =
  with_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Valid Target") ~content:(Content.make "Body") ()) in
    let specs = [
      Service.{ target = Identifier.to_string (Todo.niceid todo);
                kind = "depends-on"; bidirectional = false; blocking = false };
      Service.{ target = "kb-999"; kind = "depends-on"; bidirectional = false; blocking = false };
    ] in
    (match Service.add_note_with_relations service
             ~title:(Title.make "My Note") ~content:(Content.make "Body")
             ~specs with
     | Ok _ -> print_endline "unexpected success"
     | Error err -> pp_error err);
    query_count root "note";
    query_count root "relation");
  [%expect {|
    validation error: item not found: kb-999
    note=0
    relation=0
  |}]
