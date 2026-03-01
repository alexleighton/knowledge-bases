open Perf_harness

(* --- Scenario 1: Single-add latency at scale --- *)

let scenario_single_add ~samples tiers =
  Printf.printf "--- single-add-todo (%d samples, 1 warm-up) ---\n" samples;
  List.iter (fun n_items ->
    let num_todos, num_notes, num_relations = hetero_mix n_items in
    with_benchmark_dir (fun ~dir ->
      run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"];
      populate ~dir ~namespace:"kb" ~num_todos ~num_notes ~num_relations;
      save_baseline ~dir;
      (* Warm-up *)
      ignore (run_bs_timed ~dir ~stdin:"warmup" ["add"; "todo"; "Warmup"]);
      restore_baseline ~dir;
      (* Collect samples *)
      let timings = List.init samples (fun _ ->
        restore_baseline ~dir;
        run_bs_timed ~dir ~stdin:"bench content" ["add"; "todo"; "Bench"]) in
      print_tier ~label:"" ~n_items (compute_stats timings))
  ) tiers;
  print_newline ()

(* --- Scenarios 2 & 3: Sequential add throughput --- *)

let scenario_sequential_add ~samples ~ops tiers =
  Printf.printf "--- add-todo-burst (%d samples, %d ops, 1 warm-up) ---\n"
    samples ops;
  List.iter (fun initial ->
    with_benchmark_dir (fun ~dir ->
      run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"];
      if initial > 0 then begin
        let num_todos, num_notes, num_relations = hetero_mix initial in
        populate ~dir ~namespace:"kb" ~num_todos ~num_notes ~num_relations
      end;
      save_baseline ~dir;
      (* Warm-up *)
      for i = 1 to ops do
        ignore (run_bs_timed ~dir
                  ~stdin:(Printf.sprintf "warmup %d" i)
                  ["add"; "todo"; Printf.sprintf "Warmup-%d" i])
      done;
      restore_baseline ~dir;
      (* Collect samples *)
      let timings = List.init samples (fun _ ->
        restore_baseline ~dir;
        let total = ref 0.0 in
        for i = 1 to ops do
          total := !total +.
            run_bs_timed ~dir
              ~stdin:(Printf.sprintf "bench %d" i)
              ["add"; "todo"; Printf.sprintf "Bench-%d" i]
        done;
        !total) in
      let s = compute_stats timings in
      Printf.printf "  %5d initial    %3d ops    median %8s total   %8s/op\n"
        initial ops
        (ms_of_seconds s.median) (ms_of_seconds (s.median /. Float.of_int ops)))
  ) tiers;
  print_newline ()

(* --- Scenario 4: Rebuild at scale --- *)

let scenario_rebuild ~samples tiers =
  Printf.printf "--- rebuild (%d samples, 1 warm-up) ---\n" samples;
  List.iter (fun n_items ->
    let num_todos, num_notes, num_relations = hetero_mix n_items in
    with_benchmark_dir (fun ~dir ->
      run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"];
      generate_jsonl ~path:(jsonl_path dir) ~namespace:"kb"
        ~num_todos ~num_notes ~num_relations;
      let jsonl_backup = jsonl_path dir ^ ".baseline" in
      copy_file ~src:(jsonl_path dir) ~dst:jsonl_backup;
      (* Reset: delete DB, re-init, restore JSONL *)
      let reset () =
        (if Sys.file_exists (db_path dir) then Sys.remove (db_path dir));
        run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"];
        copy_file ~src:jsonl_backup ~dst:(jsonl_path dir)
      in
      (* Warm-up *)
      reset ();
      ignore (run_bs_timed ~dir ["rebuild"]);
      (* Collect samples *)
      let timings = List.init samples (fun _ ->
        reset ();
        run_bs_timed ~dir ["rebuild"]) in
      print_tier ~label:"" ~n_items (compute_stats timings))
  ) tiers;
  print_newline ()

(* --- Scenario 5: Read operation latency at scale --- *)

let scenario_read_ops ~samples =
  Printf.printf "--- read-ops (%d samples, 1 warm-up) ---\n" samples;
  let n_items = 10000 in
  let num_todos, num_notes, num_relations = hetero_mix n_items in
  with_benchmark_dir (fun ~dir ->
    run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"];
    populate ~dir ~namespace:"kb" ~num_todos ~num_notes ~num_relations;
    (* list-todo *)
    ignore (run_bs_timed ~dir ["list"; "todo"]);
    let list_timings = List.init samples (fun _ ->
      run_bs_timed ~dir ["list"; "todo"]) in
    print_tier ~label:"list-todo" ~n_items (compute_stats list_timings);
    (* show kb-0 — note_typeid 0 is a relation target, gets niceid kb-0 *)
    ignore (run_bs_timed ~dir ["show"; "kb-0"]);
    let show_timings = List.init samples (fun _ ->
      run_bs_timed ~dir ["show"; "kb-0"]) in
    print_tier ~label:"show" ~n_items (compute_stats show_timings));
  print_newline ()

(* --- Scenario 6: Flush cost in isolation --- *)

let scenario_flush ~samples =
  Printf.printf "--- flush (%d samples, 1 warm-up) ---\n" samples;
  let n_items = 10000 in
  let num_todos, num_notes, num_relations = hetero_mix n_items in
  with_benchmark_dir (fun ~dir ->
    run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"];
    populate ~dir ~namespace:"kb" ~num_todos ~num_notes ~num_relations;
    (* Warm-up *)
    ignore (run_bs_timed ~dir ["flush"]);
    (* Collect samples — flush calls mark_dirty, so each run does full work *)
    let timings = List.init samples (fun _ ->
      run_bs_timed ~dir ["flush"]) in
    print_tier ~label:"" ~n_items (compute_stats timings));
  print_newline ()

(* --- Scenario 7: Homogeneous vs heterogeneous comparison --- *)

let scenario_entity_mix ~samples =
  Printf.printf "--- entity-mix-comparison (%d samples, 1 warm-up) ---\n" samples;
  let n_items = 10000 in
  let configs = [
    ("todos-only", n_items, 0, 0);
    ("mixed", 4000, 4000, 2000);
  ] in
  List.iter (fun (mix_label, num_todos, num_notes, num_relations) ->
    (* Flush benchmark *)
    with_benchmark_dir (fun ~dir ->
      run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"];
      populate ~dir ~namespace:"kb" ~num_todos ~num_notes ~num_relations;
      ignore (run_bs_timed ~dir ["flush"]);
      let timings = List.init samples (fun _ ->
        run_bs_timed ~dir ["flush"]) in
      print_tier
        ~label:(Printf.sprintf "flush %s" mix_label)
        ~n_items (compute_stats timings));
    (* Rebuild benchmark *)
    with_benchmark_dir (fun ~dir ->
      run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"];
      generate_jsonl ~path:(jsonl_path dir) ~namespace:"kb"
        ~num_todos ~num_notes ~num_relations;
      let jsonl_backup = jsonl_path dir ^ ".baseline" in
      copy_file ~src:(jsonl_path dir) ~dst:jsonl_backup;
      let reset () =
        (if Sys.file_exists (db_path dir) then Sys.remove (db_path dir));
        run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"];
        copy_file ~src:jsonl_backup ~dst:(jsonl_path dir)
      in
      reset ();
      ignore (run_bs_timed ~dir ["rebuild"]);
      let timings = List.init samples (fun _ ->
        reset ();
        run_bs_timed ~dir ["rebuild"]) in
      print_tier
        ~label:(Printf.sprintf "rebuild %s" mix_label)
        ~n_items (compute_stats timings))
  ) configs;
  print_newline ()
