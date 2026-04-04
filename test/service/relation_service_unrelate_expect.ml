module Root = Kbases.Repository.Root
module RelationService = Kbases.Service.Relation_service
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Todo = Kbases.Data.Todo
module Identifier = Kbases.Data.Identifier
module Relation_kind = Kbases.Data.Relation_kind

open Test_helpers

let with_relation_service f =
  with_service RelationService.init f

let pp_error = pp_item_error

let%expect_test "unrelate removes existing relation" =
  with_relation_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Source") ~content:(Content.make "Body") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Target") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid t0) in
    let tgt = Identifier.to_string (Todo.niceid t1) in
    let specs = [{ RelationService.target = tgt; kind = "depends-on";
                   bidirectional = false; blocking = true }] in
    ignore (RelationService.relate_many service ~source:src ~specs);
    query_relations root;
    let unspecs = [{ RelationService.target = tgt; kind = "depends-on";
                     bidirectional = false }] in
    (match RelationService.unrelate_many service ~source:src ~specs:unspecs with
     | Ok results ->
         List.iter (fun (r : RelationService.unrelate_result) ->
           Printf.printf "removed: %s %s %s\n"
             (Identifier.to_string r.source_niceid)
             (Relation_kind.to_string r.kind)
             (Identifier.to_string r.target_niceid)) results
     | Error err -> pp_error err);
    query_relations root);
  [%expect {|
    kb-0|depends-on|kb-1|0
    removed: kb-0 depends-on kb-1
  |}]

let%expect_test "unrelate bidirectional from either endpoint" =
  with_relation_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "A") ~content:(Content.make "Body") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "B") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid t0) in
    let tgt = Identifier.to_string (Todo.niceid t1) in
    let specs = [{ RelationService.target = tgt; kind = "related-to";
                   bidirectional = true; blocking = false }] in
    ignore (RelationService.relate_many service ~source:src ~specs);
    query_relations root;
    (* unrelate from the other side *)
    let unspecs = [{ RelationService.target = src; kind = "related-to";
                     bidirectional = true }] in
    (match RelationService.unrelate_many service ~source:tgt ~specs:unspecs with
     | Ok results ->
         List.iter (fun (r : RelationService.unrelate_result) ->
           Printf.printf "removed: %s %s %s bidi=%b\n"
             (Identifier.to_string r.source_niceid)
             (Relation_kind.to_string r.kind)
             (Identifier.to_string r.target_niceid)
             r.bidirectional) results
     | Error err -> pp_error err);
    query_relations root);
  [%expect {|
    kb-0|related-to|kb-1|1
    removed: kb-1 related-to kb-0 bidi=true
  |}]

let%expect_test "unrelate non-existent relation returns error" =
  with_relation_service (fun root service ->
    let t0 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "A") ~content:(Content.make "Body") ()) in
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "B") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid t0) in
    let tgt = Identifier.to_string (Todo.niceid t1) in
    let specs = [{ RelationService.target = tgt; kind = "depends-on";
                   bidirectional = false }] in
    match RelationService.unrelate_many service ~source:src ~specs with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: relation not found |}]
