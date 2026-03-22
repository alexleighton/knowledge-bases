module TodoRepo = Repository.Todo
module NoteRepo = Repository.Note


type t = {
  items        : Item_service.t;
  todo_repo    : TodoRepo.t;
  note_repo    : NoteRepo.t;
  relation_svc : Relation_service.t;
}

type claim_error =
  | Not_a_todo of string
  | Not_open of { niceid : string; status : string }
  | Blocked of { niceid : string; blocked_by : string list }
  | Nothing_available of { stuck_count : int }
  | Service_error of Item_service.error

let init root = {
  items        = Item_service.init root;
  todo_repo    = Repository.Root.todo root;
  note_repo    = Repository.Root.note root;
  relation_svc = Relation_service.init root;
}

let _entity_changed (type a s) (module E : Data.Entity.S with type t = a and type status = s) old curr =
  E.status old <> E.status curr
  || E.title old <> E.title curr
  || E.content old <> E.content curr

let update t ~identifier ?status ?title ?content () =
  let open Item_service in
  match status, title, content with
  | None, None, None -> Error (Validation_error "nothing to update")
  | _ ->
      let open Result.Syntax in
      let* item = find t.items ~identifier in
      match item with
      | Todo_item old ->
          let* todo =
            match status with
            | None -> Ok old
            | Some s -> let+ s = Parse.todo_status s in Data.Todo.with_status old s
          in
          let todo = match title with None -> todo | Some t -> Data.Todo.with_title todo t in
          let todo = match content with None -> todo | Some c -> Data.Todo.with_content todo c in
          if not (_entity_changed (module Data.Todo) old todo) then
            Error (Validation_error "nothing to update")
          else
            let todo = Data.Todo.with_updated_at todo (Data.Timestamp.now ()) in
            let+ todo = TodoRepo.update t.todo_repo todo |> Result.map_error map_todo_repo_error in
            Todo_item todo
      | Note_item old ->
          let* note =
            match status with
            | None -> Ok old
            | Some s -> let+ s = Parse.note_status s in Data.Note.with_status old s
          in
          let note = match title with None -> note | Some t -> Data.Note.with_title note t in
          let note = match content with None -> note | Some c -> Data.Note.with_content note c in
          if not (_entity_changed (module Data.Note) old note) then
            Error (Validation_error "nothing to update")
          else
            let note = Data.Note.with_updated_at note (Data.Timestamp.now ()) in
            let+ note = NoteRepo.update t.note_repo note |> Result.map_error map_note_repo_error in
            Note_item note

let _transition_to t ~identifier ~entity_type ~target_status ~verb =
  let open Item_service in
  let open Result.Syntax in
  let* item = find t.items ~identifier in
  let actual_type = Data.Item.entity_type item in
  if actual_type <> entity_type then
    let niceid_str = Data.Identifier.to_string (Data.Item.niceid item) in
    Error (Validation_error
      (Printf.sprintf "%s applies only to %ss, but %s is a %s"
         verb entity_type niceid_str actual_type))
  else
    update t ~identifier ~status:target_status ()

let resolve t ~identifier =
  let open Result.Syntax in
  let+ item = _transition_to t ~identifier ~entity_type:"todo"
                ~target_status:"done" ~verb:"resolve" in
  match item with
  | Item_service.Todo_item todo -> todo
  | Item_service.Note_item _ -> assert false

let _start_todo t todo =
  let todo = Data.Todo.with_status todo Data.Todo.In_Progress in
  let todo = Data.Todo.with_updated_at todo (Data.Timestamp.now ()) in
  TodoRepo.update t.todo_repo todo
  |> Result.map_error (fun e -> Service_error (Item_service.map_todo_repo_error e))

let next t =
  let open Result.Syntax in
  let* todos = TodoRepo.list t.todo_repo ~statuses:[Data.Todo.Open]
               |> Result.map_error (fun e -> Service_error (Item_service.map_todo_repo_error e)) in
  let rec find_available stuck_count = function
    | [] ->
        if stuck_count = 0 then Ok None
        else Error (Nothing_available { stuck_count })
    | todo :: rest ->
        let* blockers = Relation_service.find_blockers t.relation_svc todo
                        |> Result.map_error (fun e -> Service_error e) in
        match blockers with
        | [] ->
            let+ todo = _start_todo t todo in
            Some todo
        | _ -> find_available (stuck_count + 1) rest
  in
  find_available 0 todos

let claim t ~identifier =
  let open Result.Syntax in
  let* item = Item_service.find t.items ~identifier
              |> Result.map_error (fun e -> Service_error e) in
  match item with
  | Item_service.Note_item _ -> Error (Not_a_todo identifier)
  | Item_service.Todo_item todo ->
      let niceid_str = Data.Identifier.to_string (Data.Todo.niceid todo) in
      match Data.Todo.status todo with
      | Data.Todo.Open ->
          let* blockers = Relation_service.find_blockers t.relation_svc todo
                          |> Result.map_error (fun e -> Service_error e) in
          (match blockers with
           | [] -> _start_todo t todo
           | _ -> Error (Blocked { niceid = niceid_str; blocked_by = blockers }))
      | Data.Todo.In_Progress | Data.Todo.Done as s ->
          Error (Not_open { niceid = niceid_str;
                            status = Data.Todo.status_to_string s })

let archive t ~identifier =
  let open Result.Syntax in
  let+ item = _transition_to t ~identifier ~entity_type:"note"
                ~target_status:"archived" ~verb:"archive" in
  match item with
  | Item_service.Note_item note -> note
  | Item_service.Todo_item _ -> assert false

let reopen t ~identifier =
  let open Item_service in
  let open Result.Syntax in
  let* item = find t.items ~identifier in
  match item with
  | Todo_item todo ->
      (match Data.Todo.status todo with
       | Data.Todo.Done ->
           update t ~identifier ~status:"open" ()
       | Data.Todo.Open | Data.Todo.In_Progress ->
           Error (Validation_error
             (Printf.sprintf "%s is not in a terminal state (status: %s)"
                identifier (Data.Todo.status_to_string (Data.Todo.status todo)))))
  | Note_item note ->
      (match Data.Note.status note with
       | Data.Note.Archived ->
           update t ~identifier ~status:"active" ()
       | Data.Note.Active ->
           Error (Validation_error
             (Printf.sprintf "%s is not in a terminal state (status: %s)"
                identifier (Data.Note.status_to_string (Data.Note.status note)))))

let resolve_many t ~identifiers =
  Data.Result.traverse (fun id -> resolve t ~identifier:id) identifiers

let archive_many t ~identifiers =
  Data.Result.traverse (fun id -> archive t ~identifier:id) identifiers

let reopen_many t ~identifiers =
  Data.Result.traverse (fun id -> reopen t ~identifier:id) identifiers
