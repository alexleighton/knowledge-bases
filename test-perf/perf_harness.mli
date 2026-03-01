val generate_jsonl :
  path:string -> namespace:string ->
  num_todos:int -> num_notes:int -> num_relations:int -> unit

val with_benchmark_dir : (dir:string -> 'a) -> 'a

val run_bs : dir:string -> ?stdin:string -> string list -> unit
val run_bs_timed : dir:string -> ?stdin:string -> string list -> float

val db_path : string -> string
val jsonl_path : string -> string
val copy_file : src:string -> dst:string -> unit
val save_baseline : dir:string -> unit
val restore_baseline : dir:string -> unit
val populate :
  dir:string -> namespace:string ->
  num_todos:int -> num_notes:int -> num_relations:int -> unit

type stats = {
  median : float;
  min : float;
  max : float;
  stddev : float;
}

val compute_stats : float list -> stats
val ms_of_seconds : float -> string
val print_tier : label:string -> n_items:int -> stats -> unit
val hetero_mix : int -> int * int * int
