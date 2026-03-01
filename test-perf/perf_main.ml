open Perf_scenarios

let scenarios = [
  ("single-add", "S1: Single-add latency at scale");
  ("sequential-add", "S2/S3: Sequential add throughput");
  ("rebuild", "S4: Rebuild at scale");
  ("read-ops", "S5: Read operation latency at scale");
  ("flush", "S6: Flush cost in isolation");
  ("entity-mix", "S7: Homogeneous vs heterogeneous comparison");
]

let run_scenario ~samples name =
  match name with
  | "single-add" -> scenario_single_add ~samples [100; 1000; 10000]
  | "sequential-add" ->
    scenario_sequential_add ~samples ~ops:50 [0; 10000]
  | "rebuild" -> scenario_rebuild ~samples [100; 1000; 10000]
  | "read-ops" -> scenario_read_ops ~samples
  | "flush" -> scenario_flush ~samples
  | "entity-mix" -> scenario_entity_mix ~samples
  | other ->
    Printf.eprintf "Unknown scenario: %s\nValid scenarios: %s\n" other
      (String.concat ", " (List.map fst scenarios));
    exit 1

let () =
  let samples = ref 5 in
  let scenario = ref "all" in
  let args = Array.to_list Sys.argv |> List.tl in
  let rec parse = function
    | "--samples" :: n :: rest ->
      samples := int_of_string n;
      parse rest
    | "--scenario" :: s :: rest ->
      scenario := s;
      parse rest
    | [] -> ()
    | arg :: _ ->
      Printf.eprintf "Unknown argument: %s\n" arg;
      exit 1
  in
  parse args;
  let t_start = Unix.gettimeofday () in
  Printf.printf "=== bs performance suite ===\n";
  Printf.printf "  samples: %d\n" !samples;
  Printf.printf "  scenario: %s\n\n" !scenario;
  if !scenario = "all" then
    List.iter (fun (name, _desc) -> run_scenario ~samples:!samples name) scenarios
  else
    run_scenario ~samples:!samples !scenario;
  let elapsed = Unix.gettimeofday () -. t_start in
  Printf.printf "=== done in %.1fs ===\n" elapsed
