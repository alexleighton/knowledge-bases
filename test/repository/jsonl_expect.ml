module Jsonl = Kbases.Repository.Jsonl
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Typeid = Kbases.Data.Uuid.Typeid

let _todo_id s = Typeid.of_string ("todo_" ^ s)
let _note_id s = Typeid.of_string ("note_" ^ s)

let _unwrap = function
  | Ok v -> v
  | Error (Jsonl.Io_error msg) -> failwith ("io error: " ^ msg)
  | Error (Jsonl.Parse_error msg) -> failwith ("parse error: " ^ msg)

let%expect_test "write and read round-trip with todos, notes, relations" =
  let tmp = Filename.temp_file "jsonl_test" ".jsonl" in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let tid1 = _todo_id "0123456789abcdefghjkmnpqrs" in
    let tid2 = _todo_id "0123456789abcdefghjkmnpqrt" in
    let nid1 = _note_id "0123456789abcdefghjkmnpqrs" in
    let niceid = Kbases.Data.Identifier.make "kb" 0 in
    let t1 = Todo.make tid1 niceid (Title.make "First todo") (Content.make "Body one") Todo.Open in
    let t2 = Todo.make tid2 niceid (Title.make "Second todo") (Content.make "Body two") Todo.Done in
    let n1 = Note.make nid1 niceid (Title.make "A note") (Content.make "Note body") Note.Active in
    let r1 = Relation.make ~source:tid1 ~target:nid1
      ~kind:(Relation_kind.make "blocks") ~bidirectional:false in

    let hash = _unwrap (Jsonl.write ~path:tmp ~namespace:"kb"
      ~todos:[t1; t2] ~notes:[n1] ~relations:[r1]) in
    Printf.printf "hash length=%d\n" (String.length hash);

    let (header, records) = _unwrap (Jsonl.read ~path:tmp) in
    Printf.printf "version=%d namespace=%s entity_count=%d\n"
      header.version header.namespace header.entity_count;
    Printf.printf "hash match=%b\n" (String.equal hash header.content_hash);
    Printf.printf "record count=%d\n" (List.length records);

    List.iter (fun record ->
      match record with
      | Jsonl.Todo { id; title; status; _ } ->
          Printf.printf "todo id=%s title=%s status=%s\n"
            (Typeid.to_string id) (Title.to_string title)
            (Todo.status_to_string status)
      | Jsonl.Note { id; title; status; _ } ->
          Printf.printf "note id=%s title=%s status=%s\n"
            (Typeid.to_string id) (Title.to_string title)
            (Note.status_to_string status)
      | Jsonl.Relation rel ->
          Printf.printf "relation src=%s tgt=%s kind=%s bidi=%b\n"
            (Typeid.to_string (Relation.source rel))
            (Typeid.to_string (Relation.target rel))
            (Relation_kind.to_string (Relation.kind rel))
            (Relation.is_bidirectional rel)
    ) records);
  [%expect {|
    hash length=32
    version=1 namespace=kb entity_count=4
    hash match=true
    record count=4
    note id=note_0123456789abcdefghjkmnpqrs title=A note status=active
    relation src=todo_0123456789abcdefghjkmnpqrs tgt=note_0123456789abcdefghjkmnpqrs kind=blocks bidi=false
    todo id=todo_0123456789abcdefghjkmnpqrs title=First todo status=open
    todo id=todo_0123456789abcdefghjkmnpqrt title=Second todo status=done
    |}]

let%expect_test "content hash is deterministic" =
  let tmp1 = Filename.temp_file "jsonl_test" ".jsonl" in
  let tmp2 = Filename.temp_file "jsonl_test" ".jsonl" in
  Fun.protect ~finally:(fun () -> Sys.remove tmp1; Sys.remove tmp2) (fun () ->
    let tid = _todo_id "0123456789abcdefghjkmnpqrs" in
    let niceid = Kbases.Data.Identifier.make "kb" 0 in
    let todo = Todo.make tid niceid (Title.make "Hello") (Content.make "World") Todo.Open in

    let h1 = _unwrap (Jsonl.write ~path:tmp1 ~namespace:"kb"
      ~todos:[todo] ~notes:[] ~relations:[]) in
    let h2 = _unwrap (Jsonl.write ~path:tmp2 ~namespace:"kb"
      ~todos:[todo] ~notes:[] ~relations:[]) in
    Printf.printf "hashes equal=%b\n" (String.equal h1 h2));
  [%expect {|
    hashes equal=true
    |}]

let%expect_test "read_header returns only header" =
  let tmp = Filename.temp_file "jsonl_test" ".jsonl" in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let tid = _todo_id "0123456789abcdefghjkmnpqrs" in
    let niceid = Kbases.Data.Identifier.make "kb" 0 in
    let todo = Todo.make tid niceid (Title.make "Hello") (Content.make "World") Todo.Open in

    let hash = _unwrap (Jsonl.write ~path:tmp ~namespace:"kb"
      ~todos:[todo] ~notes:[] ~relations:[]) in

    let header = _unwrap (Jsonl.read_header ~path:tmp) in
    Printf.printf "version=%d entity_count=%d hash_match=%b\n"
      header.version header.entity_count
      (String.equal hash header.content_hash));
  [%expect {|
    version=1 entity_count=1 hash_match=true
    |}]

let%expect_test "empty entities produce valid file" =
  let tmp = Filename.temp_file "jsonl_test" ".jsonl" in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let _hash = _unwrap (Jsonl.write ~path:tmp ~namespace:"kb"
      ~todos:[] ~notes:[] ~relations:[]) in
    let (header, records) = _unwrap (Jsonl.read ~path:tmp) in
    Printf.printf "entity_count=%d records=%d\n"
      header.entity_count (List.length records));
  [%expect {|
    entity_count=0 records=0
    |}]

let%expect_test "parse error on invalid type field" =
  let tmp = Filename.temp_file "jsonl_test" ".jsonl" in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let oc = open_out tmp in
    output_string oc {|{"_kbases":"1","namespace":"kb","entity_count":1,"content_hash":"abc"}|};
    output_char oc '\n';
    output_string oc {|{"type":"unknown","id":"todo_0123456789abcdefghjkmnpqrs"}|};
    output_char oc '\n';
    close_out oc;
    match Jsonl.read ~path:tmp with
    | Ok _ -> print_endline "unexpected success"
    | Error (Jsonl.Parse_error msg) -> Printf.printf "parse error: %s\n" msg
    | Error (Jsonl.Io_error msg) -> Printf.printf "io error: %s\n" msg);
  [%expect {|
    parse error: unknown entity type: "unknown"
    |}]

let%expect_test "parse error on missing header" =
  let tmp = Filename.temp_file "jsonl_test" ".jsonl" in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let oc = open_out tmp in
    close_out oc;
    match Jsonl.read_header ~path:tmp with
    | Ok _ -> print_endline "unexpected success"
    | Error (Jsonl.Parse_error msg) -> Printf.printf "parse error: %s\n" msg
    | Error (Jsonl.Io_error msg) -> Printf.printf "io error: %s\n" msg);
  [%expect {|
    parse error: empty file, no header line
    |}]
