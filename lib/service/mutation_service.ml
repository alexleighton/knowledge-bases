module TodoRepo = Repository.Todo
module NoteRepo = Repository.Note
module RelationRepo = Repository.Relation

type t = {
  items         : Item_service.t;
  todo_repo     : TodoRepo.t;
  note_repo     : NoteRepo.t;
  relation_repo : RelationRepo.t;
}

type claim_error =
  | Not_a_todo of string
  | Not_open of { niceid : string; status : string }
  | Blocked of { niceid : string; blocked_by : string list }
  | Nothing_available of { stuck_count : int }
  | Service_error of Item_service.error

let init root = {
  items         = Item_service.init root;
  todo_repo     = Repository.Root.todo root;
  note_repo     = Repository.Root.note root;
  relation_repo = Repository.Root.relation root;
}

let _map_relation_repo_error = function
  | RelationRepo.Duplicate ->
      Item_service.Validation_error "relation already exists"
  | RelationRepo.Backend_failure msg ->
      Item_service.Repository_error msg

let _is_blocked t todo =
  let typeid = Data.Todo.id todo in
  match RelationRepo.find_by_source t.relation_repo typeid with
  | Error err -> Error (_map_relation_repo_error err)
  | Ok rels ->
      let blocking = List.filter Data.Relation.is_blocking rels in
      let blockers =
        List.filter_map (fun rel ->
          let target_id = Data.Uuid.Typeid.to_string (Data.Relation.target rel) in
          match Item_service.find t.items ~identifier:target_id with
          | Ok (Item_service.Todo_item target_todo) ->
              if Data.Todo.status target_todo <> Data.Todo.Done then
                Some (Data.Identifier.to_string (Data.Todo.niceid target_todo))
              else None
          | Ok (Item_service.Note_item _) -> None
          | Error _ -> None
        ) blocking
      in
      Ok blockers

let update t ~identifier ?status ?title ?content () =
  let open Item_service in
  match status, title, content with
  | None, None, None -> Error (Validation_error "nothing to update")
  | _ ->
      let open Result.Syntax in
      let* item = find t.items ~identifier in
      match item with
      | Todo_item todo ->
          let* todo =
            match status with
            | None -> Ok todo
            | Some s -> let+ s = Parse.todo_status s in Data.Todo.with_status todo s
          in
          let todo = match title with None -> todo | Some t -> Data.Todo.with_title todo t in
          let todo = match content with None -> todo | Some c -> Data.Todo.with_content todo c in
          let+ todo = TodoRepo.update t.todo_repo todo |> Result.map_error map_todo_repo_error in
          Todo_item todo
      | Note_item note ->
          let* note =
            match status with
            | None -> Ok note
            | Some s -> let+ s = Parse.note_status s in Data.Note.with_status note s
          in
          let note = match title with None -> note | Some t -> Data.Note.with_title note t in
          let note = match content with None -> note | Some c -> Data.Note.with_content note c in
          let+ note = NoteRepo.update t.note_repo note |> Result.map_error map_note_repo_error in
          Note_item note

let resolve t ~identifier =
  let open Item_service in
  let open Result.Syntax in
  let* item = find t.items ~identifier in
  match item with
  | Note_item note ->
      let niceid_str = Data.Identifier.to_string (Data.Note.niceid note) in
      Error (Validation_error
        (Printf.sprintf "resolve applies only to todos, but %s is a note" niceid_str))
  | Todo_item todo ->
      let todo = Data.Todo.with_status todo Data.Todo.Done in
      TodoRepo.update t.todo_repo todo |> Result.map_error map_todo_repo_error

let next t =
  let open Result.Syntax in
  let* todos = TodoRepo.list t.todo_repo ~statuses:[Data.Todo.Open]
               |> Result.map_error (fun e -> Service_error (Item_service.map_todo_repo_error e)) in
  let rec find_available stuck_count = function
    | [] ->
        if stuck_count = 0 then Ok None
        else Error (Nothing_available { stuck_count })
    | todo :: rest ->
        let* blockers = _is_blocked t todo
                        |> Result.map_error (fun e -> Service_error e) in
        match blockers with
        | [] ->
            let todo = Data.Todo.with_status todo Data.Todo.In_Progress in
            let+ todo = TodoRepo.update t.todo_repo todo
                        |> Result.map_error (fun e -> Service_error (Item_service.map_todo_repo_error e)) in
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
          let* blockers = _is_blocked t todo
                          |> Result.map_error (fun e -> Service_error e) in
          (match blockers with
           | [] ->
               let todo = Data.Todo.with_status todo Data.Todo.In_Progress in
               TodoRepo.update t.todo_repo todo
               |> Result.map_error (fun e -> Service_error (Item_service.map_todo_repo_error e))
           | _ -> Error (Blocked { niceid = niceid_str; blocked_by = blockers }))
      | Data.Todo.In_Progress | Data.Todo.Done as s ->
          Error (Not_open { niceid = niceid_str;
                            status = Data.Todo.status_to_string s })

let archive t ~identifier =
  let open Item_service in
  let open Result.Syntax in
  let* item = find t.items ~identifier in
  match item with
  | Todo_item todo ->
      let niceid_str = Data.Identifier.to_string (Data.Todo.niceid todo) in
      Error (Validation_error
        (Printf.sprintf "archive applies only to notes, but %s is a todo" niceid_str))
  | Note_item note ->
      let note = Data.Note.with_status note Data.Note.Archived in
      NoteRepo.update t.note_repo note |> Result.map_error map_note_repo_error
