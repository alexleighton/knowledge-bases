module Root = Kbases.Repository.Root
module RelationRepo = Kbases.Repository.Relation
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module TodoRepo = Kbases.Repository.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content

let with_root = Test_helpers.with_root
let query_rows = Test_helpers.query_rows

let make_todo root title =
  match TodoRepo.create (Root.todo root)
    ~title:(Title.make title) ~content:(Content.make "body") () with
  | Ok todo -> todo
  | Error _ -> failwith "todo creation failed"

(** Query stored relations with niceids resolved via a join on the todo
    table. Prints [source_niceid|kind|target_niceid|bidirectional] per row. *)
let query_relations root =
  query_rows root
    {|SELECT s.niceid, r.kind, t.niceid, r.bidirectional
      FROM relation r
      JOIN todo s ON s.id = r.source
      JOIN todo t ON t.id = r.target
      ORDER BY s.niceid, r.kind|}
    []

let pp_error = function
  | RelationRepo.Duplicate -> print_endline "error: duplicate"
  | RelationRepo.Not_found -> print_endline "error: not found"
  | RelationRepo.Backend_failure msg -> Printf.printf "error: backend failure: %s\n" msg

let%expect_test "create relation and verify row in DB" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let kind = Relation_kind.make "depends-on" in
    let rel = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:false ~blocking:false in
    (match RelationRepo.create (Root.relation root) rel with
     | Ok r ->
         Printf.printf "created: kind=%s bidi=%b\n"
           (Relation_kind.to_string (Relation.kind r))
           (Relation.is_bidirectional r)
     | Error err -> pp_error err);
    query_relations root);
  [%expect {|
    created: kind=depends-on bidi=false
    kb-0|depends-on|kb-1|0
  |}]

let%expect_test "exact duplicate returns Duplicate" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let kind = Relation_kind.make "depends-on" in
    let rel = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:false ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) rel);
    match RelationRepo.create (Root.relation root) rel with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| error: duplicate |}]

let%expect_test "bidirectional reverse duplicate returns Duplicate" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let kind = Relation_kind.make "related-to" in
    let forward = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:true ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) forward);
    let reverse = Relation.make ~source:tgt ~target:src ~kind ~bidirectional:true ~blocking:false in
    match RelationRepo.create (Root.relation root) reverse with
    | Ok _ -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| error: duplicate |}]

let%expect_test "unidirectional reverse is allowed" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let kind = Relation_kind.make "depends-on" in
    let forward = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:false ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) forward);
    let reverse = Relation.make ~source:tgt ~target:src ~kind ~bidirectional:false ~blocking:false in
    match RelationRepo.create (Root.relation root) reverse with
    | Ok r ->
        Printf.printf "created reverse: kind=%s\n"
          (Relation_kind.to_string (Relation.kind r))
    | Error err -> pp_error err);
  [%expect {| created reverse: kind=depends-on |}]

let%expect_test "list_all returns all relations" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let t3 = make_todo root "Third" in
    let src1 = Kbases.Data.Todo.id t1 in
    let tgt1 = Kbases.Data.Todo.id t2 in
    let src2 = Kbases.Data.Todo.id t2 in
    let tgt2 = Kbases.Data.Todo.id t3 in
    let k1 = Relation_kind.make "depends-on" in
    let k2 = Relation_kind.make "related-to" in
    let r1 = Relation.make ~source:src1 ~target:tgt1 ~kind:k1 ~bidirectional:false ~blocking:false in
    let r2 = Relation.make ~source:src2 ~target:tgt2 ~kind:k2 ~bidirectional:true ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) r1);
    ignore (RelationRepo.create (Root.relation root) r2);
    match RelationRepo.list_all (Root.relation root) with
    | Ok rels ->
        Printf.printf "list_all count=%d\n" (List.length rels);
        let sorted = List.sort (fun a b ->
          compare
            (Relation_kind.to_string (Relation.kind a))
            (Relation_kind.to_string (Relation.kind b))
        ) rels in
        List.iter (fun rel ->
          Printf.printf "kind=%s bidi=%b\n"
            (Relation_kind.to_string (Relation.kind rel))
            (Relation.is_bidirectional rel)
        ) sorted
    | Error err -> pp_error err);
  [%expect {|
    list_all count=2
    kind=depends-on bidi=false
    kind=related-to bidi=true
  |}]

let%expect_test "delete_all removes all relations" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let kind = Relation_kind.make "depends-on" in
    let rel = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:false ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) rel);
    (match RelationRepo.delete_all (Root.relation root) with
     | Ok () -> print_endline "delete_all ok"
     | Error err -> pp_error err);
    match RelationRepo.list_all (Root.relation root) with
    | Ok rels -> Printf.printf "after delete_all count=%d\n" (List.length rels)
    | Error err -> pp_error err);
  [%expect {|
    delete_all ok
    after delete_all count=0
  |}]

let%expect_test "same pair with different kind is allowed" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let k1 = Relation_kind.make "depends-on" in
    let k2 = Relation_kind.make "related-to" in
    let r1 = Relation.make ~source:src ~target:tgt ~kind:k1 ~bidirectional:false ~blocking:false in
    let r2 = Relation.make ~source:src ~target:tgt ~kind:k2 ~bidirectional:true ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) r1);
    (match RelationRepo.create (Root.relation root) r2 with
     | Ok _ -> print_endline "second kind ok"
     | Error err -> pp_error err);
    query_relations root);
  [%expect {|
    second kind ok
    kb-0|depends-on|kb-1|0
    kb-0|related-to|kb-1|1
  |}]

let%expect_test "delete relation then list_all is empty" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let kind = Relation_kind.make "depends-on" in
    let rel = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:false ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) rel);
    (match RelationRepo.delete (Root.relation root) ~source:src ~target:tgt ~kind ~bidirectional:false with
     | Ok () -> print_endline "delete ok"
     | Error err -> pp_error err);
    match RelationRepo.list_all (Root.relation root) with
    | Ok rels -> Printf.printf "after delete count=%d\n" (List.length rels)
    | Error err -> pp_error err);
  [%expect {|
    delete ok
    after delete count=0
  |}]

let%expect_test "delete bidirectional relation from reverse endpoint" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let kind = Relation_kind.make "related-to" in
    let rel = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:true ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) rel);
    (* Delete using reversed source/target — should succeed for bidirectional *)
    (match RelationRepo.delete (Root.relation root) ~source:tgt ~target:src ~kind ~bidirectional:true with
     | Ok () -> print_endline "reverse delete ok"
     | Error err -> pp_error err);
    match RelationRepo.list_all (Root.relation root) with
    | Ok rels -> Printf.printf "after delete count=%d\n" (List.length rels)
    | Error err -> pp_error err);
  [%expect {|
    reverse delete ok
    after delete count=0
  |}]

let%expect_test "delete non-existent relation returns Not_found" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let kind = Relation_kind.make "depends-on" in
    match RelationRepo.delete (Root.relation root) ~source:src ~target:tgt ~kind ~bidirectional:false with
    | Ok () -> print_endline "unexpected success"
    | Error err -> pp_error err);
  [%expect {| error: not found |}]

let%expect_test "delete_by_entity removes all relations involving entity" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let t3 = make_todo root "Third" in
    let id1 = Kbases.Data.Todo.id t1 in
    let id2 = Kbases.Data.Todo.id t2 in
    let id3 = Kbases.Data.Todo.id t3 in
    let k1 = Relation_kind.make "depends-on" in
    let k2 = Relation_kind.make "related-to" in
    (* t1 -> t2, t3 -> t1: both involve t1 *)
    let r1 = Relation.make ~source:id1 ~target:id2 ~kind:k1 ~bidirectional:false ~blocking:false in
    let r2 = Relation.make ~source:id3 ~target:id1 ~kind:k2 ~bidirectional:false ~blocking:false in
    (* t2 -> t3: does not involve t1 *)
    let r3 = Relation.make ~source:id2 ~target:id3 ~kind:k1 ~bidirectional:false ~blocking:false in
    ignore (RelationRepo.create (Root.relation root) r1);
    ignore (RelationRepo.create (Root.relation root) r2);
    ignore (RelationRepo.create (Root.relation root) r3);
    (match RelationRepo.delete_by_entity (Root.relation root) id1 with
     | Ok n -> Printf.printf "deleted count=%d\n" n
     | Error err -> pp_error err);
    match RelationRepo.list_all (Root.relation root) with
    | Ok rels ->
        Printf.printf "remaining count=%d\n" (List.length rels);
        query_relations root
    | Error err -> pp_error err);
  [%expect {|
    deleted count=2
    remaining count=1
    kb-1|depends-on|kb-2|0
  |}]
