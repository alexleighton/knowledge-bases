module Jsonl = Kbases.Repository.Jsonl
module Todo = Kbases.Data.Todo
module Note = Kbases.Data.Note
module Relation = Kbases.Data.Relation
module Relation_kind = Kbases.Data.Relation_kind
module Title = Kbases.Data.Title
module Content = Kbases.Data.Content
module Typeid = Kbases.Data.Uuid.Typeid
module Timestamp = Kbases.Data.Timestamp

let todo_id s = Typeid.of_string ("todo_" ^ s)
let note_id s = Typeid.of_string ("note_" ^ s)

let unwrap = function
  | Ok v -> v
  | Error (Jsonl.Io_error msg) -> failwith ("io error: " ^ msg)
  | Error (Jsonl.Parse_error msg) -> failwith ("parse error: " ^ msg)

let with_tmp_jsonl f =
  let tmp = Filename.temp_file "jsonl_test" ".jsonl" in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () -> f tmp)

let%expect_test "write and read round-trip with todos, notes, relations" =
  with_tmp_jsonl (fun tmp ->
    let tid1 = todo_id "0123456789abcdefghjkmnpqrs" in
    let tid2 = todo_id "0123456789abcdefghjkmnpqrt" in
    let nid1 = note_id "0123456789abcdefghjkmnpqrs" in
    let niceid = Kbases.Data.Identifier.make "kb" 0 in
    let t1 = Todo.make tid1 niceid (Title.make "First todo") (Content.make "Body one") Todo.Open ~created_at:(Timestamp.make 1710000000) ~updated_at:(Timestamp.make 1710003600) in
    let t2 = Todo.make tid2 niceid (Title.make "Second todo") (Content.make "Body two") Todo.Done ~created_at:(Timestamp.make 1710000000) ~updated_at:(Timestamp.make 1710000000) in
    let n1 = Note.make nid1 niceid (Title.make "A note") (Content.make "Note body") Note.Active ~created_at:(Timestamp.make 1710000000) ~updated_at:(Timestamp.make 1710000000) in
    let r1 = Relation.make ~source:tid1 ~target:nid1
      ~kind:(Relation_kind.make "blocks") ~bidirectional:false ~blocking:false in

    let () = unwrap (Jsonl.write ~path:tmp ~namespace:"kb"
      ~todos:[t1; t2] ~notes:[n1] ~relations:[r1]) in

    let (header, records) = unwrap (Jsonl.read ~path:tmp) in
    Printf.printf "version=%d namespace=%s\n"
      header.version header.namespace;
    Printf.printf "record count=%d\n" (List.length records);

    List.iter (fun record ->
      match record with
      | Jsonl.Todo { id; title; status; created_at; updated_at; _ } ->
          Printf.printf "todo id=%s title=%s status=%s created=%d updated=%d\n"
            (Typeid.to_string id) (Title.to_string title)
            (Todo.status_to_string status) (Timestamp.to_epoch created_at) (Timestamp.to_epoch updated_at)
      | Jsonl.Note { id; title; status; created_at; updated_at; _ } ->
          Printf.printf "note id=%s title=%s status=%s created=%d updated=%d\n"
            (Typeid.to_string id) (Title.to_string title)
            (Note.status_to_string status) (Timestamp.to_epoch created_at) (Timestamp.to_epoch updated_at)
      | Jsonl.Relation rel ->
          Printf.printf "relation src=%s tgt=%s kind=%s bidi=%b\n"
            (Typeid.to_string (Relation.source rel))
            (Typeid.to_string (Relation.target rel))
            (Relation_kind.to_string (Relation.kind rel))
            (Relation.is_bidirectional rel)
    ) records);
  [%expect {|
    version=1 namespace=kb
    record count=4
    note id=note_0123456789abcdefghjkmnpqrs title=A note status=active created=1710000000 updated=1710000000
    relation src=todo_0123456789abcdefghjkmnpqrs tgt=note_0123456789abcdefghjkmnpqrs kind=blocks bidi=false
    todo id=todo_0123456789abcdefghjkmnpqrs title=First todo status=open created=1710000000 updated=1710003600
    todo id=todo_0123456789abcdefghjkmnpqrt title=Second todo status=done created=1710000000 updated=1710000000
    |}]

let%expect_test "file hash is deterministic" =
  with_tmp_jsonl (fun tmp1 ->
  with_tmp_jsonl (fun tmp2 ->
    let tid = todo_id "0123456789abcdefghjkmnpqrs" in
    let niceid = Kbases.Data.Identifier.make "kb" 0 in
    let todo = Todo.make tid niceid (Title.make "Hello") (Content.make "World") Todo.Open ~created_at:(Timestamp.make 1710000000) ~updated_at:(Timestamp.make 1710000000) in

    let () = unwrap (Jsonl.write ~path:tmp1 ~namespace:"kb"
      ~todos:[todo] ~notes:[] ~relations:[]) in
    let () = unwrap (Jsonl.write ~path:tmp2 ~namespace:"kb"
      ~todos:[todo] ~notes:[] ~relations:[]) in
    let h1 = Digest.file tmp1 |> Digest.to_hex in
    let h2 = Digest.file tmp2 |> Digest.to_hex in
    Printf.printf "hashes equal=%b\n" (String.equal h1 h2)));
  [%expect {|
    hashes equal=true
    |}]

let%expect_test "empty entities produce valid file" =
  with_tmp_jsonl (fun tmp ->
    let () = unwrap (Jsonl.write ~path:tmp ~namespace:"kb"
      ~todos:[] ~notes:[] ~relations:[]) in
    let (_header, records) = unwrap (Jsonl.read ~path:tmp) in
    Printf.printf "records=%d\n" (List.length records));
  [%expect {|
    records=0
    |}]

let%expect_test "parser ignores extra header fields (old format)" =
  with_tmp_jsonl (fun tmp ->
    let oc = open_out tmp in
    output_string oc {|{"_kbases":"1","namespace":"kb","entity_count":1,"content_hash":"abc"}|};
    output_char oc '\n';
    close_out oc;
    let (header, records) = unwrap (Jsonl.read ~path:tmp) in
    Printf.printf "version=%d namespace=%s records=%d\n"
      header.version header.namespace (List.length records));
  [%expect {|
    version=1 namespace=kb records=0
    |}]

let%expect_test "parse error on invalid type field" =
  with_tmp_jsonl (fun tmp ->
    let oc = open_out tmp in
    output_string oc {|{"_kbases":"1","namespace":"kb"}|};
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

let%expect_test "read_header returns namespace from valid file" =
  with_tmp_jsonl (fun tmp ->
    let () = unwrap (Jsonl.write ~path:tmp ~namespace:"myns"
      ~todos:[] ~notes:[] ~relations:[]) in
    let header = unwrap (Jsonl.read_header ~path:tmp) in
    Printf.printf "version=%d namespace=%s\n"
      header.version header.namespace);
  [%expect {|
    version=1 namespace=myns
  |}]

let%expect_test "read_header fails on empty file" =
  with_tmp_jsonl (fun tmp ->
    let oc = open_out tmp in
    close_out oc;
    match Jsonl.read_header ~path:tmp with
    | Ok _ -> print_endline "unexpected success"
    | Error (Jsonl.Parse_error msg) -> Printf.printf "parse error: %s\n" msg
    | Error (Jsonl.Io_error msg) -> Printf.printf "io error: %s\n" msg);
  [%expect {|
    parse error: empty file, no header line
  |}]

let%expect_test "read_header fails on corrupt JSON" =
  with_tmp_jsonl (fun tmp ->
    let oc = open_out tmp in
    output_string oc "not json at all\n";
    close_out oc;
    match Jsonl.read_header ~path:tmp with
    | Ok _ -> print_endline "unexpected success"
    | Error (Jsonl.Parse_error _) -> print_endline "parse error"
    | Error (Jsonl.Io_error _) -> print_endline "io error");
  [%expect {|
    parse error
  |}]

let%expect_test "read_header fails on missing file" =
  (match Jsonl.read_header ~path:"/tmp/nonexistent_jsonl_file.jsonl" with
   | Ok _ -> print_endline "unexpected success"
   | Error (Jsonl.Io_error _) -> print_endline "io error"
   | Error (Jsonl.Parse_error _) -> print_endline "parse error");
  [%expect {|
    io error
  |}]

let%expect_test "parse error on missing header" =
  with_tmp_jsonl (fun tmp ->
    let oc = open_out tmp in
    close_out oc;
    match Jsonl.read ~path:tmp with
    | Ok _ -> print_endline "unexpected success"
    | Error (Jsonl.Parse_error msg) -> Printf.printf "parse error: %s\n" msg
    | Error (Jsonl.Io_error msg) -> Printf.printf "io error: %s\n" msg);
  [%expect {|
    parse error: empty file, no header line
    |}]
