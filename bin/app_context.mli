type t
val init : unit -> t
val service : t -> Kbases.Service.Kb_service.t
val close : t -> unit
