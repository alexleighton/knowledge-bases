module Root = Kbases.Repository.Root
module TodoRepo = Kbases.Repository.Todo
module NoteRepo = Kbases.Repository.Note
module RelationRepo = Kbases.Repository.Relation
module GcService = Kbases.Service.Gc_service
module ConfigService = Kbases.Service.Config_service
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module Timestamp = Kbases.Data.Timestamp

let unwrap_todo = Test_helpers.unwrap_todo_repo
let unwrap_note = Test_helpers.unwrap_note_repo
let query_count = Test_helpers.query_count
let pp_error = Test_helpers.pp_item_error

let with_gc_service f =
  Test_helpers.with_service
    (fun root -> GcService.init root
      ~config_svc:(ConfigService.init root ~dir:Test_helpers.dir_without_kbases_jsonl))
    f

let now = 1000000
let old_ts = 0         (* very old *)
let recent_ts = 999999 (* within 1 day of now *)
let max_age = 86400    (* 1 day *)

(* Create a todo with specific timestamps via import *)
let make_todo root ~title ~status ~ts =
  let id = Todo.make_id () in
  unwrap_todo (TodoRepo.import (Root.todo root)
    ~id ~title:(Title.make title) ~content:(Content.make "Body")
    ~status ~created_at:(Timestamp.make ts) ~updated_at:(Timestamp.make ts) ())

let make_note root ~title ~status ~ts =
  let id = Note.make_id () in
  unwrap_note (NoteRepo.import (Root.note root)
    ~id ~title:(Title.make title) ~content:(Content.make "Body")
    ~status ~created_at:(Timestamp.make ts) ~updated_at:(Timestamp.make ts) ())

let make_rel root ~source ~target =
  let rel = Relation.make ~source:(Todo.id source) ~target:(Todo.id target)
    ~kind:(Relation_kind.make "depends-on") ~bidirectional:false ~blocking:true in
  match RelationRepo.create (Root.relation root) rel with
  | Ok _ -> () | Error _ -> failwith "create relation failed"

let%expect_test "terminal items older than max_age are collected" =
  with_gc_service (fun root service ->
    ignore (make_todo root ~title:"Old done" ~status:Todo.Done ~ts:old_ts);
    ignore (make_todo root ~title:"Recent open" ~status:Todo.Open ~ts:recent_ts);
    match GcService.collect service ~max_age_seconds:max_age ~now with
    | Ok items ->
        Printf.printf "eligible=%d\n" (List.length items);
        List.iter (fun (i : GcService.gc_item) ->
          Printf.printf "  %s %s\n" i.entity_type
            (Identifier.to_string i.niceid)) items
    | Error err -> pp_error err);
  [%expect {|
    eligible=1
      todo kb-0
  |}]

let%expect_test "terminal item reachable from non-terminal is retained" =
  with_gc_service (fun root service ->
    let open_todo = make_todo root ~title:"Open" ~status:Todo.Open ~ts:old_ts in
    let done_todo = make_todo root ~title:"Done" ~status:Todo.Done ~ts:old_ts in
    make_rel root ~source:open_todo ~target:done_todo;
    match GcService.collect service ~max_age_seconds:max_age ~now with
    | Ok items ->
        Printf.printf "eligible=%d\n" (List.length items)
    | Error err -> pp_error err);
  [%expect {| eligible=0 |}]

let%expect_test "entire component of old terminal items is removed" =
  with_gc_service (fun root service ->
    let t0 = make_todo root ~title:"Done A" ~status:Todo.Done ~ts:old_ts in
    let t1 = make_todo root ~title:"Done B" ~status:Todo.Done ~ts:old_ts in
    make_rel root ~source:t0 ~target:t1;
    match GcService.collect service ~max_age_seconds:max_age ~now with
    | Ok items ->
        Printf.printf "eligible=%d\n" (List.length items)
    | Error err -> pp_error err);
  [%expect {| eligible=2 |}]

let%expect_test "cycle of old terminal items is collected" =
  with_gc_service (fun root service ->
    let t0 = make_todo root ~title:"A" ~status:Todo.Done ~ts:old_ts in
    let t1 = make_todo root ~title:"B" ~status:Todo.Done ~ts:old_ts in
    let t2 = make_todo root ~title:"C" ~status:Todo.Done ~ts:old_ts in
    make_rel root ~source:t0 ~target:t1;
    make_rel root ~source:t1 ~target:t2;
    make_rel root ~source:t2 ~target:t0;
    match GcService.collect service ~max_age_seconds:max_age ~now with
    | Ok items ->
        Printf.printf "eligible=%d\n" (List.length items)
    | Error err -> pp_error err);
  [%expect {| eligible=3 |}]

let%expect_test "cycle with one non-terminal retains entire cycle" =
  with_gc_service (fun root service ->
    let t0 = make_todo root ~title:"Done" ~status:Todo.Done ~ts:old_ts in
    let t1 = make_todo root ~title:"Open" ~status:Todo.Open ~ts:old_ts in
    let t2 = make_todo root ~title:"Done2" ~status:Todo.Done ~ts:old_ts in
    make_rel root ~source:t0 ~target:t1;
    make_rel root ~source:t1 ~target:t2;
    make_rel root ~source:t2 ~target:t0;
    match GcService.collect service ~max_age_seconds:max_age ~now with
    | Ok items ->
        Printf.printf "eligible=%d\n" (List.length items)
    | Error err -> pp_error err);
  [%expect {| eligible=0 |}]

let%expect_test "run removes items and returns correct counts" =
  with_gc_service (fun root service ->
    let t0 = make_todo root ~title:"Done A" ~status:Todo.Done ~ts:old_ts in
    let t1 = make_todo root ~title:"Done B" ~status:Todo.Done ~ts:old_ts in
    make_rel root ~source:t0 ~target:t1;
    ignore (make_todo root ~title:"Open" ~status:Todo.Open ~ts:recent_ts);
    (match GcService.run service ~max_age_seconds:max_age ~now with
     | Ok r ->
         Printf.printf "removed=%d relations=%d\n"
           r.items_removed r.relations_removed
     | Error err -> pp_error err);
    query_count root "todo";
    query_count root "relation");
  [%expect {|
    removed=2 relations=1
    todo=1
    relation=0
  |}]

let%expect_test "collect returns items without removing them" =
  with_gc_service (fun root service ->
    ignore (make_todo root ~title:"Old done" ~status:Todo.Done ~ts:old_ts);
    (match GcService.collect service ~max_age_seconds:max_age ~now with
     | Ok items -> Printf.printf "eligible=%d\n" (List.length items)
     | Error err -> pp_error err);
    query_count root "todo");
  [%expect {|
    eligible=1
    todo=1
  |}]

let%expect_test "archived note older than max_age is collected" =
  with_gc_service (fun root service ->
    ignore (make_note root ~title:"Old archived" ~status:Note.Archived ~ts:old_ts);
    ignore (make_note root ~title:"Recent active" ~status:Note.Active ~ts:recent_ts);
    match GcService.collect service ~max_age_seconds:max_age ~now with
    | Ok items ->
        Printf.printf "eligible=%d\n" (List.length items);
        List.iter (fun (i : GcService.gc_item) ->
          Printf.printf "  %s %s\n" i.entity_type
            (Identifier.to_string i.niceid)) items
    | Error err -> pp_error err);
  [%expect {|
    eligible=1
      note kb-0
  |}]
