(** Extended result module.

    Includes all functions from {!Stdlib.Result} plus list traversal. *)

include module type of Stdlib.Result

(** Traverse a list of results, stopping on the first [Error]. *)
val sequence : ('a, 'e) result list -> ('a list, 'e) result

(** [traverse f xs] maps [f] over [xs], short-circuiting on the first [Error].
    Unlike [List.map f xs |> sequence], [f] is never called for elements after
    the first failure. *)
val traverse : ('a -> ('b, 'e) result) -> 'a list -> ('b list, 'e) result
