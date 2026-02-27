module Root = Kbases.Repository.Root
module RelationRepo = Kbases.Repository.Relation
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module Typeid = Kbases.Data.Uuid.Typeid
module Sqlite = Kbases.Repository.Sqlite
module TodoRepo = Kbases.Repository.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content

let query_rows root sql params =
  let db = Root.db root in
  match Sqlite.with_stmt db sql params (fun stmt ->
    let n = Sqlite3.data_count stmt in
    Ok (List.init n (fun i -> Sqlite3.column_text stmt i) |> String.concat "|"))
  with
  | Ok rows -> List.iter print_endline rows
  | Error err -> Printf.printf "query error: %s\n" (Sqlite.error_message err)

let with_root f =
  match Root.init ~db_file:":memory:" ~namespace:(Some "kb") with
  | Ok root ->
      Fun.protect ~finally:(fun () -> Root.close root) (fun () -> f root)
  | Error (Root.Backend_failure msg) -> failwith ("init error: " ^ msg)

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
  | RelationRepo.Backend_failure msg -> Printf.printf "error: backend failure: %s\n" msg

let%expect_test "create relation and verify row in DB" =
  with_root (fun root ->
    let t1 = make_todo root "First" in
    let t2 = make_todo root "Second" in
    let src = Kbases.Data.Todo.id t1 in
    let tgt = Kbases.Data.Todo.id t2 in
    let kind = Relation_kind.make "depends-on" in
    let rel = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:false in
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
    let rel = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:false in
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
    let forward = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:true in
    ignore (RelationRepo.create (Root.relation root) forward);
    let reverse = Relation.make ~source:tgt ~target:src ~kind ~bidirectional:true in
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
    let forward = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:false in
    ignore (RelationRepo.create (Root.relation root) forward);
    let reverse = Relation.make ~source:tgt ~target:src ~kind ~bidirectional:false in
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
    let r1 = Relation.make ~source:src1 ~target:tgt1 ~kind:k1 ~bidirectional:false in
    let r2 = Relation.make ~source:src2 ~target:tgt2 ~kind:k2 ~bidirectional:true in
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
    let rel = Relation.make ~source:src ~target:tgt ~kind ~bidirectional:false in
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
    let r1 = Relation.make ~source:src ~target:tgt ~kind:k1 ~bidirectional:false in
    let r2 = Relation.make ~source:src ~target:tgt ~kind:k2 ~bidirectional:true in
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
