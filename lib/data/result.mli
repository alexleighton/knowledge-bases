(** Extended result module.

    Includes all functions from {!Stdlib.Result} plus list traversal. *)

include module type of Stdlib.Result

(** Traverse a list of results, stopping on the first [Error]. *)
val sequence : ('a, 'e) result list -> ('a list, 'e) result
