module CA = Control.Assert

type t = int

let make epoch =
  CA.requiref (epoch >= 0) "Timestamp must be non-negative, got %d" epoch;
  epoch

let now () = Float.to_int (Unix.gettimeofday ())

let to_epoch t = t

let compare = Int.compare

let _fmt_tm (t : Unix.tm) =
  let open Unix in
  (t.tm_year + 1900, t.tm_mon + 1, t.tm_mday,
   t.tm_hour, t.tm_min, t.tm_sec)

let to_iso8601 epoch =
  let (y, mo, d, h, mi, se) = _fmt_tm (Unix.gmtime (Float.of_int epoch)) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" y mo d h mi se

let of_iso8601 s =
  try
    Scanf.sscanf s "%4d-%2d-%2dT%2d:%2d:%2dZ"
      (fun y mo d h mi se ->
         let tm = {
           Unix.tm_sec = se; tm_min = mi; tm_hour = h;
           tm_mday = d; tm_mon = mo - 1; tm_year = y - 1900;
           tm_wday = 0; tm_yday = 0; tm_isdst = false;
         } in
         (* mktime interprets tm as local time, but we need UTC.
            To recover the correct epoch: run mktime → gmtime → mktime.
            The difference between the two mktime results is the
            local-to-UTC offset at this point in time, which accounts
            for DST.  Adding that offset to the first result gives the
            UTC epoch.  (OCaml does not expose timegm(3).) *)
         let (local_epoch, _) = Unix.mktime tm in
         let utc_tm = Unix.gmtime local_epoch in
         let (utc_epoch, _) = Unix.mktime utc_tm in
         let offset = local_epoch -. utc_epoch in
         Ok (make (Float.to_int (local_epoch +. offset))))
  with
  | Scanf.Scan_failure _ | End_of_file | Failure _ ->
    Error (Printf.sprintf "Invalid ISO 8601 timestamp: %S" s)

let to_display epoch =
  let (y, mo, d, h, mi, se) = _fmt_tm (Unix.gmtime (Float.of_int epoch)) in
  Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d UTC" y mo d h mi se

let pp fmt t = Format.pp_print_int fmt t
let show t = string_of_int t
