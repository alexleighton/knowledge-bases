module Root = Kbases.Repository.Root
module TodoRepo = Kbases.Repository.Todo
module RelationRepo = Kbases.Repository.Relation
module GraphService = Kbases.Service.Graph_service
module Todo = Kbases.Data.Todo
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Identifier = Kbases.Data.Identifier
module Typeid = Kbases.Data.Uuid.Typeid
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind

let unwrap_todo = Test_helpers.unwrap_todo_repo

let with_graph_service f =
  Test_helpers.with_service GraphService.init f

let make_rel root ~source ~target ~kind ~bidi =
  let rel = Relation.make ~source:(Todo.id source) ~target:(Todo.id target)
    ~kind:(Relation_kind.make kind) ~bidirectional:bidi ~blocking:false in
  match RelationRepo.create (Root.relation root) rel with
  | Ok r -> r | Error _ -> failwith "create relation failed"

let pp_ids ids =
  let strs = List.map (fun id ->
    let s = Typeid.to_string id in
    (* extract last 3 chars for readability *)
    String.sub s (String.length s - 3) 3
  ) ids in
  Printf.printf "[%s]\n" (String.concat ", " (List.sort String.compare strs))

let pp_error = Test_helpers.pp_item_error

(* Helper: create N todos, return them in order *)
let make_todos root n =
  List.init n (fun i ->
    unwrap_todo (TodoRepo.create (Root.todo root)
      ~title:(Title.make (Printf.sprintf "T%d" i))
      ~content:(Content.make "Body") ()))

let pp_niceids root ids =
  let strs = List.map (fun id ->
    let id_str = Typeid.to_string id in
    match TodoRepo.get (Root.todo root) (Typeid.of_string id_str) with
    | Ok t -> Identifier.to_string (Todo.niceid t)
    | Error _ -> id_str
  ) ids in
  Printf.printf "[%s]\n" (String.concat ", " (List.sort String.compare strs))

let%expect_test "linear chain A->B->C, reachable_from A outgoing" =
  with_graph_service (fun root service ->
    let todos = make_todos root 3 in
    let a = List.nth todos 0 and b = List.nth todos 1 and c = List.nth todos 2 in
    ignore (make_rel root ~source:a ~target:b ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:b ~target:c ~kind:"depends-on" ~bidi:false);
    match GraphService.reachable_from service
            ~typeid:(Todo.id a) ~kind:None ~direction:Outgoing with
    | Ok ids -> pp_niceids root ids
    | Error err -> pp_error err);
  [%expect {| [kb-1, kb-2] |}]

let%expect_test "reachable_from C incoming returns A, B" =
  with_graph_service (fun root service ->
    let todos = make_todos root 3 in
    let a = List.nth todos 0 and b = List.nth todos 1 and c = List.nth todos 2 in
    ignore (make_rel root ~source:a ~target:b ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:b ~target:c ~kind:"depends-on" ~bidi:false);
    match GraphService.reachable_from service
            ~typeid:(Todo.id c) ~kind:None ~direction:Incoming with
    | Ok ids -> pp_niceids root ids
    | Error err -> pp_error err);
  [%expect {| [kb-0, kb-1] |}]

let%expect_test "diamond graph, no duplicates" =
  with_graph_service (fun root service ->
    let todos = make_todos root 4 in
    let a = List.nth todos 0 and b = List.nth todos 1
    and c = List.nth todos 2 and d = List.nth todos 3 in
    ignore (make_rel root ~source:a ~target:b ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:a ~target:c ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:b ~target:d ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:c ~target:d ~kind:"depends-on" ~bidi:false);
    match GraphService.reachable_from service
            ~typeid:(Todo.id a) ~kind:None ~direction:Outgoing with
    | Ok ids ->
        Printf.printf "count=%d\n" (List.length ids);
        pp_niceids root ids
    | Error err -> pp_error err);
  [%expect {|
    count=3
    [kb-1, kb-2, kb-3]
  |}]

let%expect_test "cycle A->B->C->A, BFS terminates" =
  with_graph_service (fun root service ->
    let todos = make_todos root 3 in
    let a = List.nth todos 0 and b = List.nth todos 1 and c = List.nth todos 2 in
    ignore (make_rel root ~source:a ~target:b ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:b ~target:c ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:c ~target:a ~kind:"depends-on" ~bidi:false);
    match GraphService.reachable_from service
            ~typeid:(Todo.id a) ~kind:None ~direction:Outgoing with
    | Ok ids ->
        Printf.printf "count=%d\n" (List.length ids);
        pp_niceids root ids
    | Error err -> pp_error err);
  [%expect {|
    count=2
    [kb-1, kb-2]
  |}]

let%expect_test "kind filter only follows matching relations" =
  with_graph_service (fun root service ->
    let todos = make_todos root 3 in
    let a = List.nth todos 0 and b = List.nth todos 1 and c = List.nth todos 2 in
    ignore (make_rel root ~source:a ~target:b ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:a ~target:c ~kind:"related-to" ~bidi:true);
    let kind = Some (Relation_kind.make "depends-on") in
    match GraphService.reachable_from service
            ~typeid:(Todo.id a) ~kind ~direction:Outgoing with
    | Ok ids -> pp_niceids root ids
    | Error err -> pp_error err);
  [%expect {| [kb-1] |}]

let%expect_test "connected_component returns entire component" =
  with_graph_service (fun root service ->
    let todos = make_todos root 4 in
    let a = List.nth todos 0 and b = List.nth todos 1
    and c = List.nth todos 2 and _d = List.nth todos 3 in
    ignore (make_rel root ~source:a ~target:b ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:b ~target:c ~kind:"related-to" ~bidi:true);
    (* d is disconnected *)
    match GraphService.connected_component service ~typeid:(Todo.id a) with
    | Ok ids ->
        Printf.printf "count=%d\n" (List.length ids);
        pp_niceids root ids
    | Error err -> pp_error err);
  [%expect {|
    count=3
    [kb-0, kb-1, kb-2]
  |}]

let%expect_test "connected_component on cycle returns exactly cycle" =
  with_graph_service (fun root service ->
    let todos = make_todos root 4 in
    let a = List.nth todos 0 and b = List.nth todos 1
    and c = List.nth todos 2 and _d = List.nth todos 3 in
    ignore (make_rel root ~source:a ~target:b ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:b ~target:c ~kind:"depends-on" ~bidi:false);
    ignore (make_rel root ~source:c ~target:a ~kind:"depends-on" ~bidi:false);
    match GraphService.connected_component service ~typeid:(Todo.id b) with
    | Ok ids ->
        Printf.printf "count=%d\n" (List.length ids);
        pp_niceids root ids
    | Error err -> pp_error err);
  [%expect {|
    count=3
    [kb-0, kb-1, kb-2]
  |}]

let%expect_test "disconnected item not included" =
  with_graph_service (fun root service ->
    let todos = make_todos root 3 in
    let a = List.nth todos 0 and b = List.nth todos 1 and _c = List.nth todos 2 in
    ignore (make_rel root ~source:a ~target:b ~kind:"depends-on" ~bidi:false);
    match GraphService.connected_component service ~typeid:(Todo.id a) with
    | Ok ids ->
        Printf.printf "count=%d\n" (List.length ids);
        pp_niceids root ids
    | Error err -> pp_error err);
  [%expect {|
    count=2
    [kb-0, kb-1]
  |}]
