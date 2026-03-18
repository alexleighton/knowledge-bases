module Root = Kbases.Repository.Root
module TodoRepo = Kbases.Repository.Todo
module NoteRepo = Kbases.Repository.Note
module RelationRepo = Kbases.Repository.Relation
module DeleteService = Kbases.Service.Delete_service
module ItemService = Kbases.Service.Item_service
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind

let unwrap_todo_repo = Test_helpers.unwrap_todo_repo
let unwrap_note_repo = Test_helpers.unwrap_note_repo
let query_count = Test_helpers.query_count

let with_delete_service f =
  Test_helpers.with_service DeleteService.init f

let pp_error = function
  | DeleteService.Blocked_dependency { niceid; dependents } ->
      Printf.printf "blocked: %s by [%s]\n" niceid (String.concat "; " dependents)
  | DeleteService.Service_error err -> Test_helpers.pp_item_error err

let%expect_test "delete item removes it from list and show" =
  with_delete_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()) in
    let niceid_str = Identifier.to_string (Todo.niceid todo) in
    (match DeleteService.delete service ~identifier:niceid_str ~force:false with
     | Ok r ->
         Printf.printf "deleted %s: %s rels=%d\n"
           r.entity_type (Identifier.to_string r.niceid) r.relations_removed
     | Error err -> pp_error err);
    query_count root "todo");
  [%expect {|
    deleted todo: kb-0 rels=0
    todo=0
  |}]

let%expect_test "delete item with relations removes relations" =
  with_delete_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Source") ~content:(Content.make "Body") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Target") ~content:(Content.make "Body") ()) in
    let rel = Relation.make ~source:(Todo.id t0) ~target:(Todo.id t1)
      ~kind:(Relation_kind.make "related-to") ~bidirectional:true ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) rel);
    let niceid_str = Identifier.to_string (Todo.niceid t0) in
    (match DeleteService.delete service ~identifier:niceid_str ~force:false with
     | Ok r ->
         Printf.printf "deleted %s: %s rels=%d\n"
           r.entity_type (Identifier.to_string r.niceid) r.relations_removed
     | Error err -> pp_error err);
    query_count root "todo";
    query_count root "relation");
  [%expect {|
    deleted todo: kb-0 rels=1
    todo=1
    relation=0
  |}]

let%expect_test "delete blocked item returns error" =
  with_delete_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Blocker") ~content:(Content.make "Body") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Depends") ~content:(Content.make "Body") ()) in
    let rel = Relation.make ~source:(Todo.id t1) ~target:(Todo.id t0)
      ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true in
    ignore (RelationRepo.create (Root.relation root) rel);
    let niceid_str = Identifier.to_string (Todo.niceid t0) in
    match DeleteService.delete service ~identifier:niceid_str ~force:false with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    blocked: kb-0 by [kb-1]
  |}]

let%expect_test "delete with force ignores blocking check" =
  with_delete_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Blocker") ~content:(Content.make "Body") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Depends") ~content:(Content.make "Body") ()) in
    let rel = Relation.make ~source:(Todo.id t1) ~target:(Todo.id t0)
      ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true in
    ignore (RelationRepo.create (Root.relation root) rel);
    let niceid_str = Identifier.to_string (Todo.niceid t0) in
    (match DeleteService.delete service ~identifier:niceid_str ~force:true with
     | Ok r ->
         Printf.printf "deleted %s: %s rels=%d\n"
           r.entity_type (Identifier.to_string r.niceid) r.relations_removed
     | Error err -> pp_error err);
    query_count root "todo";
    query_count root "relation");
  [%expect {|
    deleted todo: kb-0 rels=1
    todo=1
    relation=0
  |}]

let%expect_test "delete_many batch, one blocked fails all" =
  with_delete_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Blocked") ~content:(Content.make "Body") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Depends") ~content:(Content.make "Body") ()) in
    let _t2 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Safe") ~content:(Content.make "Body") ()) in
    let rel = Relation.make ~source:(Todo.id t1) ~target:(Todo.id t0)
      ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true in
    ignore (RelationRepo.create (Root.relation root) rel);
    (match DeleteService.delete_many service
             ~identifiers:["kb-2"; "kb-0"] ~force:false with
     | Ok _ -> print_endline "unexpected success"
     | Error err -> pp_error err);
    query_count root "todo");
  [%expect {|
    blocked: kb-0 by [kb-1]
    todo=3
  |}]

let%expect_test "delete non-existent item returns error" =
  with_delete_service (fun _root service ->
    match DeleteService.delete service ~identifier:"kb-999" ~force:false with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {|
    validation error: item not found: kb-999
  |}]

let%expect_test "delete note removes it" =
  with_delete_service (fun root service ->
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Research") ~content:(Content.make "Findings") ()) in
    let niceid_str = Identifier.to_string (Note.niceid note) in
    (match DeleteService.delete service ~identifier:niceid_str ~force:false with
     | Ok r ->
         Printf.printf "deleted %s: %s\n"
           r.entity_type (Identifier.to_string r.niceid)
     | Error err -> pp_error err);
    query_count root "note");
  [%expect {|
    deleted note: kb-0
    note=0
  |}]
