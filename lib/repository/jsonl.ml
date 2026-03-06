type entity_record =
  | Todo of { id: Data.Uuid.Typeid.t; title: Data.Title.t;
              content: Data.Content.t; status: Data.Todo.status }
  | Note of { id: Data.Uuid.Typeid.t; title: Data.Title.t;
              content: Data.Content.t; status: Data.Note.status }
  | Relation of Data.Relation.t

type header = {
  version   : int;
  namespace : string;
}

type error =
  | Io_error of string
  | Parse_error of string

(* --- Serialization --- *)

let _todo_to_json todo =
  `Assoc [
    ("type", `String "todo");
    ("id", `String (Data.Uuid.Typeid.to_string (Data.Todo.id todo)));
    ("title", `String (Data.Title.to_string (Data.Todo.title todo)));
    ("content", `String (Data.Content.to_string (Data.Todo.content todo)));
    ("status", `String (Data.Todo.status_to_string (Data.Todo.status todo)));
  ]

let _note_to_json note =
  `Assoc [
    ("type", `String "note");
    ("id", `String (Data.Uuid.Typeid.to_string (Data.Note.id note)));
    ("title", `String (Data.Title.to_string (Data.Note.title note)));
    ("content", `String (Data.Content.to_string (Data.Note.content note)));
    ("status", `String (Data.Note.status_to_string (Data.Note.status note)));
  ]

let _relation_to_json rel =
  `Assoc [
    ("type", `String "relation");
    ("source", `String (Data.Uuid.Typeid.to_string (Data.Relation.source rel)));
    ("target", `String (Data.Uuid.Typeid.to_string (Data.Relation.target rel)));
    ("kind", `String (Data.Relation_kind.to_string (Data.Relation.kind rel)));
    ("bidirectional", `Bool (Data.Relation.is_bidirectional rel));
    ("blocking", `Bool (Data.Relation.is_blocking rel));
  ]

let _sort_key_todo todo =
  Data.Uuid.Typeid.to_string (Data.Todo.id todo)

let _sort_key_note note =
  Data.Uuid.Typeid.to_string (Data.Note.id note)

let _sort_key_relation rel =
  "relation:" ^
  Data.Uuid.Typeid.to_string (Data.Relation.source rel) ^ ":" ^
  Data.Uuid.Typeid.to_string (Data.Relation.target rel) ^ ":" ^
  Data.Relation_kind.to_string (Data.Relation.kind rel)

let _header_to_json ~namespace =
  `Assoc [
    ("_kbases", `String "1");
    ("namespace", `String namespace);
  ]

let write ~path ~namespace ~todos ~notes ~relations =
  try
    let keyed =
      List.map (fun t -> (_sort_key_todo t, _todo_to_json t)) todos
      @ List.map (fun n -> (_sort_key_note n, _note_to_json n)) notes
      @ List.map (fun r -> (_sort_key_relation r, _relation_to_json r)) relations
    in
    let sorted = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) keyed in
    let entity_lines =
      List.map (fun (_, json) -> Yojson.Safe.to_string json) sorted in
    let header_json = _header_to_json ~namespace in
    let header_line = Yojson.Safe.to_string header_json in
    let full_content =
      if entity_lines = [] then header_line ^ "\n"
      else header_line ^ "\n" ^ String.concat "\n" entity_lines ^ "\n"
    in
    let tmp_path = path ^ ".tmp" in
    let oc = open_out tmp_path in
    Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      output_string oc full_content);
    Unix.rename tmp_path path;
    Ok ()
  with
  | Sys_error msg -> Error (Io_error msg)
  | exn -> Error (Io_error (Printexc.to_string exn))

(* --- Parsing --- *)

let _get_string json key =
  match json with
  | `Assoc pairs ->
      (match List.assoc_opt key pairs with
       | Some (`String s) -> Ok s
       | Some _ -> Error (Parse_error (Printf.sprintf "field %S is not a string" key))
       | None -> Error (Parse_error (Printf.sprintf "missing field %S" key)))
  | _ -> Error (Parse_error "expected JSON object")

let _get_bool json key =
  match json with
  | `Assoc pairs ->
      (match List.assoc_opt key pairs with
       | Some (`Bool b) -> Ok b
       | Some _ -> Error (Parse_error (Printf.sprintf "field %S is not a bool" key))
       | None -> Error (Parse_error (Printf.sprintf "missing field %S" key)))
  | _ -> Error (Parse_error "expected JSON object")

let _parse_header_json json =
  let open Data.Result.Syntax in
  let* version_s = _get_string json "_kbases" in
  let* () =
    if String.equal version_s "1" then Ok ()
    else Error (Parse_error (Printf.sprintf "unsupported JSONL version: %S" version_s))
  in
  let* namespace = _get_string json "namespace" in
  Ok { version = 1; namespace }

let _parse_typeid s =
  match Data.Uuid.Typeid.parse s with
  | Ok tid -> Ok tid
  | Error msg -> Error (Parse_error (Printf.sprintf "invalid TypeId %S: %s" s msg))

let _try_make f x =
  try Ok (f x)
  with Invalid_argument msg -> Error (Parse_error msg)

let _parse_todo_record json =
  let open Data.Result.Syntax in
  let* id_s = _get_string json "id" in
  let* id = _parse_typeid id_s in
  let* title_s = _get_string json "title" in
  let* content_s = _get_string json "content" in
  let* status_s = _get_string json "status" in
  let* title = _try_make Data.Title.make title_s in
  let* content = _try_make Data.Content.make content_s in
  let* status = Data.Todo.status_of_string status_s
    |> Result.map_error (fun msg -> Parse_error msg) in
  Ok (Todo { id; title; content; status })

let _parse_note_record json =
  let open Data.Result.Syntax in
  let* id_s = _get_string json "id" in
  let* id = _parse_typeid id_s in
  let* title_s = _get_string json "title" in
  let* content_s = _get_string json "content" in
  let* status_s = _get_string json "status" in
  let* title = _try_make Data.Title.make title_s in
  let* content = _try_make Data.Content.make content_s in
  let* status = Data.Note.status_of_string status_s
    |> Result.map_error (fun msg -> Parse_error msg) in
  Ok (Note { id; title; content; status })

let _get_bool_default json key default =
  match json with
  | `Assoc pairs ->
      (match List.assoc_opt key pairs with
       | Some (`Bool b) -> Ok b
       | Some _ -> Error (Parse_error (Printf.sprintf "field %S is not a bool" key))
       | None -> Ok default)
  | _ -> Error (Parse_error "expected JSON object")

let _parse_relation_record json =
  let open Data.Result.Syntax in
  let* source_s = _get_string json "source" in
  let* source = _parse_typeid source_s in
  let* target_s = _get_string json "target" in
  let* target = _parse_typeid target_s in
  let* kind_s = _get_string json "kind" in
  let* bidirectional = _get_bool json "bidirectional" in
  let* blocking = _get_bool_default json "blocking" false in
  let* kind = _try_make Data.Relation_kind.make kind_s in
  Ok (Relation (Data.Relation.make ~source ~target ~kind ~bidirectional ~blocking))

let _parse_entity_line line =
  let open Data.Result.Syntax in
  let json =
    try Ok (Yojson.Safe.from_string line)
    with Yojson.Json_error msg -> Error (Parse_error msg)
  in
  let* json = json in
  let* typ = _get_string json "type" in
  match typ with
  | "todo" -> _parse_todo_record json
  | "note" -> _parse_note_record json
  | "relation" -> _parse_relation_record json
  | other -> Error (Parse_error (Printf.sprintf "unknown entity type: %S" other))

let _parse_header_line line =
  try
    let json = Yojson.Safe.from_string line in
    _parse_header_json json
  with Yojson.Json_error msg -> Error (Parse_error msg)

let _read_lines path =
  try
    let ic = open_in path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      let rec collect acc =
        match input_line ic with
        | line -> collect (line :: acc)
        | exception End_of_file -> Ok (List.rev acc)
      in
      collect [])
  with Sys_error msg -> Error (Io_error msg)

let read_header ~path =
  try
    let ic = open_in path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      match input_line ic with
      | line -> _parse_header_line line
      | exception End_of_file ->
          Error (Parse_error "empty file, no header line"))
  with Sys_error msg -> Error (Io_error msg)

let read ~path =
  let open Data.Result.Syntax in
  let* lines = _read_lines path in
  match lines with
  | [] -> Error (Parse_error "empty file, no header line")
  | header_line :: entity_lines ->
      let* header = _parse_header_line header_line in
      let non_empty = List.filter (fun s -> String.length s > 0) entity_lines in
      let* records = Data.Result.sequence (List.map _parse_entity_line non_empty) in
      Ok (header, records)

