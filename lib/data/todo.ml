module CA = Control.Assert
module CE = Control.Exception

(** Status of a todo item. *)
type status = Open | In_Progress | Done [@@deriving show]

let status_to_string = function Open -> "open" | In_Progress -> "in-progress" | Done -> "done"

let status_from_string = function "open" -> Open | "in-progress" -> In_Progress | "done" -> Done
  | s -> CE.invalid_arg1 "Invalid status \"%s\"" s

type t = {
  note   : Note.t;
  status : status;
}
[@@deriving show]

let note   { note;   _ } = note
let status { status; _ } = status

let id t = note t |> Note.id

let make note status = {
  note   = note;
  status = status;
}
