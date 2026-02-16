(** IO helpers used by command-line frontends. *)

let read_all_stdin () =
  let buf = Buffer.create 4096 in
  try
    while true do
      Buffer.add_string buf (input_line stdin);
      Buffer.add_char buf '\n'
    done;
    assert false
  with End_of_file -> Buffer.contents buf |> String.trim
