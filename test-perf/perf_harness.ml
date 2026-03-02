(* --- Deterministic TypeId generation --- *)

let todo_typeid i = Printf.sprintf "todo_%026d" i
let note_typeid i = Printf.sprintf "note_%026d" i

(* --- JSONL generation --- *)

let todo_json ~id ~title ~content =
  `Assoc [
    ("type", `String "todo");
    ("id", `String id);
    ("title", `String title);
    ("content", `String content);
    ("status", `String "open");
  ]

let note_json ~id ~title ~content =
  `Assoc [
    ("type", `String "note");
    ("id", `String id);
    ("title", `String title);
    ("content", `String content);
    ("status", `String "active");
  ]

let relation_json ~source ~target ~kind =
  `Assoc [
    ("type", `String "relation");
    ("source", `String source);
    ("target", `String target);
    ("kind", `String kind);
    ("bidirectional", `Bool false);
  ]

let relation_sort_key ~source ~target ~kind =
  "relation:" ^ source ^ ":" ^ target ^ ":" ^ kind

let generate_jsonl ~path ~namespace ~num_todos ~num_notes ~num_relations =
  let keyed = ref [] in
  for i = 0 to num_todos - 1 do
    let id = todo_typeid i in
    let json = todo_json ~id
        ~title:(Printf.sprintf "Todo %d" i)
        ~content:(Printf.sprintf "Content for todo %d" i) in
    keyed := (id, json) :: !keyed
  done;
  for i = 0 to num_notes - 1 do
    let id = note_typeid i in
    let json = note_json ~id
        ~title:(Printf.sprintf "Note %d" i)
        ~content:(Printf.sprintf "Content for note %d" i) in
    keyed := (id, json) :: !keyed
  done;
  for i = 0 to num_relations - 1 do
    let source = todo_typeid (i mod (max 1 num_todos)) in
    let target = note_typeid (i mod (max 1 num_notes)) in
    let kind = "related-to" in
    let key = relation_sort_key ~source ~target ~kind in
    let json = relation_json ~source ~target ~kind in
    keyed := (key, json) :: !keyed
  done;
  let sorted = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) !keyed in
  let entity_lines = List.map (fun (_, json) -> Yojson.Safe.to_string json) sorted in
  let header = `Assoc [
    ("_kbases", `String "1");
    ("namespace", `String namespace);
  ] in
  let header_line = Yojson.Safe.to_string header in
  let full_content =
    if entity_lines = [] then header_line ^ "\n"
    else header_line ^ "\n" ^ String.concat "\n" entity_lines ^ "\n"
  in
  let oc = open_out path in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
    output_string oc full_content)

(* --- bs executable resolution --- *)

let find_project_root () =
  let rec search dir =
    if Sys.file_exists (Filename.concat dir "dune-project") then dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then failwith "Cannot find project root (dune-project)"
      else search parent
  in
  search (Sys.getcwd ())

let bs_exe =
  lazy
    (let root = find_project_root () in
     let exe = Filename.concat root "_build/default/bin/main.exe" in
     if Sys.file_exists exe then exe
     else failwith ("bs executable not found at " ^ exe))

(* --- Temp directory management --- *)

let rec rm_rf path =
  if Sys.file_exists path then begin
    if Sys.is_directory path then begin
      Array.iter
        (fun entry -> rm_rf (Filename.concat path entry))
        (Sys.readdir path);
      Unix.rmdir path
    end else
      Sys.remove path
  end

let with_benchmark_dir f =
  let dir = Filename.temp_dir "kb-perf-" "" in
  Unix.mkdir (Filename.concat dir ".git") 0o755;
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f ~dir)

(* --- Subprocess invocation --- *)

let dev_null_fd () = Unix.openfile "/dev/null" [Unix.O_RDWR] 0

let run_bs ~dir ?stdin:(stdin_content) args =
  let exe = Lazy.force bs_exe in
  let argv = Array.of_list (exe :: args) in
  let old_cwd = Sys.getcwd () in
  Sys.chdir dir;
  Fun.protect ~finally:(fun () -> Sys.chdir old_cwd) (fun () ->
    let stdin_r, stdin_cleanup =
      match stdin_content with
      | None ->
        let fd = dev_null_fd () in
        fd, (fun () -> Unix.close fd)
      | Some content ->
        let r, w = Unix.pipe () in
        let bytes = Bytes.of_string content in
        let _written = Unix.write w bytes 0 (Bytes.length bytes) in
        Unix.close w;
        r, (fun () -> Unix.close r)
    in
    let devnull = dev_null_fd () in
    Fun.protect ~finally:(fun () ->
      stdin_cleanup ();
      Unix.close devnull) (fun () ->
      let env = Array.append (Unix.environment ())
          [| "TERM=dumb" |] in
      let pid = Unix.create_process_env exe argv env stdin_r devnull devnull in
      let _, status = Unix.waitpid [] pid in
      match status with
      | Unix.WEXITED 0 -> ()
      | Unix.WEXITED n ->
        failwith (Printf.sprintf "bs %s exited with code %d"
                    (String.concat " " args) n)
      | Unix.WSIGNALED n ->
        failwith (Printf.sprintf "bs %s killed by signal %d"
                    (String.concat " " args) n)
      | Unix.WSTOPPED n ->
        failwith (Printf.sprintf "bs %s stopped by signal %d"
                    (String.concat " " args) n)))

let run_bs_timed ~dir ?stdin args =
  let t0 = Unix.gettimeofday () in
  run_bs ~dir ?stdin args;
  Unix.gettimeofday () -. t0

(* --- State management --- *)

let db_path dir = Filename.concat dir ".kbases.db"
let jsonl_path dir = Filename.concat dir ".kbases.jsonl"

let copy_file ~src ~dst =
  let ic = open_in_bin src in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let oc = open_out_bin dst in
    Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      let buf = Bytes.create 65536 in
      let rec loop () =
        let n = input ic buf 0 (Bytes.length buf) in
        if n > 0 then begin
          output oc buf 0 n;
          loop ()
        end
      in
      loop ()))

let save_baseline ~dir =
  copy_file ~src:(db_path dir) ~dst:(db_path dir ^ ".baseline");
  if Sys.file_exists (jsonl_path dir) then
    copy_file ~src:(jsonl_path dir) ~dst:(jsonl_path dir ^ ".baseline")

let restore_baseline ~dir =
  copy_file ~src:(db_path dir ^ ".baseline") ~dst:(db_path dir);
  let jbl = jsonl_path dir ^ ".baseline" in
  if Sys.file_exists jbl then
    copy_file ~src:jbl ~dst:(jsonl_path dir)
  else if Sys.file_exists (jsonl_path dir) then
    Sys.remove (jsonl_path dir)

let populate ~dir ~namespace ~num_todos ~num_notes ~num_relations =
  generate_jsonl ~path:(jsonl_path dir) ~namespace ~num_todos ~num_notes
    ~num_relations;
  run_bs ~dir ["rebuild"]

(* --- Statistics --- *)

type stats = {
  median : float;
  min : float;
  max : float;
  stddev : float;
}

let compute_stats samples =
  let arr = Array.of_list samples in
  Array.sort Float.compare arr;
  let n = Array.length arr in
  let median =
    if n mod 2 = 1 then arr.(n / 2)
    else (arr.(n / 2 - 1) +. arr.(n / 2)) /. 2.0
  in
  let min_v = arr.(0) in
  let max_v = arr.(n - 1) in
  let mean = Array.fold_left ( +. ) 0.0 arr /. Float.of_int n in
  let variance =
    Array.fold_left (fun acc x -> acc +. (x -. mean) ** 2.0) 0.0 arr
    /. Float.of_int n
  in
  { median; min = min_v; max = max_v; stddev = Float.sqrt variance }

(* --- Reporting --- *)

let ms_of_seconds s = Printf.sprintf "%.1fms" (s *. 1000.0)

let print_tier ~label ~n_items stats =
  Printf.printf "  %-14s %5d items    median %8s   min %8s   max %8s   stddev %8s\n"
    label n_items
    (ms_of_seconds stats.median) (ms_of_seconds stats.min)
    (ms_of_seconds stats.max) (ms_of_seconds stats.stddev)

(* Heterogeneous entity mix: 40% todos, 40% notes, 20% relations *)
let hetero_mix n =
  let num_todos = n * 2 / 5 in
  let num_notes = n * 2 / 5 in
  let num_relations = n - num_todos - num_notes in
  (num_todos, num_notes, num_relations)
