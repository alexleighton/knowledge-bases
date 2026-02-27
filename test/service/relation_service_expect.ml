module Root = Kbases.Repository.Root
module TodoRepo = Kbases.Repository.Todo
module NoteRepo = Kbases.Repository.Note
module RelationService = Kbases.Service.Relation_service
module ItemService = Kbases.Service.Item_service
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Identifier = Kbases.Data.Identifier
module Relation_kind = Kbases.Data.Relation_kind
module Relation = Kbases.Data.Relation

let unwrap_todo_repo = Test_helpers.unwrap_todo_repo
let unwrap_note_repo = Test_helpers.unwrap_note_repo
let query_rows = Test_helpers.query_rows

(** Query stored relations with niceids resolved via joins across both
    entity tables. Prints [source_niceid|kind|target_niceid|bidirectional]
    per row. *)
let query_relations root =
  query_rows root
    {|SELECT s.niceid, r.kind, t.niceid, r.bidirectional
      FROM relation r
      JOIN (SELECT id, niceid FROM todo UNION ALL SELECT id, niceid FROM note) s
        ON s.id = r.source
      JOIN (SELECT id, niceid FROM todo UNION ALL SELECT id, niceid FROM note) t
        ON t.id = r.target
      ORDER BY s.niceid, r.kind|}
    []

let with_relation_service f =
  let root =
    match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
    | Ok root -> root
    | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)
  in
  let service = RelationService.init root in
  Fun.protect
    ~finally:(fun () -> Root.close root)
    (fun () -> f root service)

let pp_error = function
  | ItemService.Repository_error msg -> Printf.printf "repository error: %s\n" msg
  | ItemService.Validation_error msg -> Printf.printf "validation error: %s\n" msg

(* -- Happy path tests -- *)

let%expect_test "relate two todos with depends-on" =
  with_relation_service (fun root service ->
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "Body") ()) in
    let t2 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid t1) in
    let tgt = Identifier.to_string (Todo.niceid t2) in
    (match RelationService.relate service ~source:src ~target:tgt
             ~kind:"depends-on" ~bidirectional:false with
     | Ok r ->
         Printf.printf "related: %s %s %s (%s)\n"
           (Identifier.to_string r.source_niceid)
           (Relation_kind.to_string (Relation.kind r.relation))
           (Identifier.to_string r.target_niceid)
           (if Relation.is_bidirectional r.relation then "bidirectional"
            else "unidirectional")
     | Error err -> pp_error err);
    query_relations root);
  [%expect {|
    related: kb-0 depends-on kb-1 (unidirectional)
    kb-0|depends-on|kb-1|0
  |}]

let%expect_test "relate todo to note with related-to" =
  with_relation_service (fun root service ->
    let todo = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Task") ~content:(Content.make "Body") ()) in
    let note = unwrap_note_repo (NoteRepo.create (Root.note root)
      ~title:(Title.make "Research") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid todo) in
    let tgt = Identifier.to_string (Note.niceid note) in
    (match RelationService.relate service ~source:src ~target:tgt
             ~kind:"related-to" ~bidirectional:true with
     | Ok r ->
         Printf.printf "related: %s %s %s (%s)\n"
           (Identifier.to_string r.source_niceid)
           (Relation_kind.to_string (Relation.kind r.relation))
           (Identifier.to_string r.target_niceid)
           (if Relation.is_bidirectional r.relation then "bidirectional"
            else "unidirectional")
     | Error err -> pp_error err);
    query_relations root);
  [%expect {|
    related: kb-0 related-to kb-1 (bidirectional)
    kb-0|related-to|kb-1|1
  |}]

let%expect_test "relate with user-defined unidirectional kind" =
  with_relation_service (fun root service ->
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "Body") ()) in
    let t2 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid t1) in
    let tgt = Identifier.to_string (Todo.niceid t2) in
    (match RelationService.relate service ~source:src ~target:tgt
            ~kind:"designed-by" ~bidirectional:false with
    | Ok r ->
        Printf.printf "related: %s %s %s\n"
          (Identifier.to_string r.source_niceid)
          (Relation_kind.to_string (Relation.kind r.relation))
          (Identifier.to_string r.target_niceid)
    | Error err -> pp_error err);
    query_relations root);
  [%expect {|
    related: kb-0 designed-by kb-1
    kb-0|designed-by|kb-1|0
  |}]

(* -- Error tests -- *)

let%expect_test "source not found" =
  with_relation_service (fun root service ->
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Target") ~content:(Content.make "Body") ()) in
    let tgt = Identifier.to_string (Todo.niceid t1) in
    match RelationService.relate service ~source:"kb-999" ~target:tgt
            ~kind:"depends-on" ~bidirectional:false with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: item not found: kb-999 |}]

let%expect_test "target not found" =
  with_relation_service (fun root service ->
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Source") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid t1) in
    match RelationService.relate service ~source:src ~target:"kb-999"
            ~kind:"depends-on" ~bidirectional:false with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: item not found: kb-999 |}]

let%expect_test "invalid kind string" =
  with_relation_service (fun root service ->
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "Body") ()) in
    let t2 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid t1) in
    let tgt = Identifier.to_string (Todo.niceid t2) in
    match RelationService.relate service ~source:src ~target:tgt
            ~kind:"BAD KIND" ~bidirectional:false with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: relation kind must match [a-z0-9][a-z0-9-]* and not end with '-' |}]

let%expect_test "duplicate relation" =
  with_relation_service (fun root service ->
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "Body") ()) in
    let t2 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid t1) in
    let tgt = Identifier.to_string (Todo.niceid t2) in
    ignore (RelationService.relate service ~source:src ~target:tgt
              ~kind:"depends-on" ~bidirectional:false);
    match RelationService.relate service ~source:src ~target:tgt
            ~kind:"depends-on" ~bidirectional:false with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: relation already exists |}]

let%expect_test "bidirectional reverse duplicate" =
  with_relation_service (fun root service ->
    let t1 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "First") ~content:(Content.make "Body") ()) in
    let t2 = unwrap_todo_repo (TodoRepo.create (Root.todo root)
      ~title:(Title.make "Second") ~content:(Content.make "Body") ()) in
    let src = Identifier.to_string (Todo.niceid t1) in
    let tgt = Identifier.to_string (Todo.niceid t2) in
    ignore (RelationService.relate service ~source:src ~target:tgt
              ~kind:"related-to" ~bidirectional:true);
    match RelationService.relate service ~source:tgt ~target:src
            ~kind:"related-to" ~bidirectional:true with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| validation error: relation already exists |}]
