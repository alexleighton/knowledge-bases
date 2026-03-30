type t
val init : unit -> t
val service : t -> Kbases.Service.Kb_service.t
val config_svc : t -> Kbases.Service.Config_service.t
val close : t -> unit
