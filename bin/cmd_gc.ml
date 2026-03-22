module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module Arg = Cmdliner.Arg

module Common = Cmdline_common
module Service = Kbases.Service.Kb_service
module Identifier = Kbases.Data.Identifier
module Title = Kbases.Data.Title

let gc_item_to_json (i : Service.Gc.gc_item) =
  let open Service.Gc in
  `Assoc [
    "niceid", `String (Identifier.to_string i.niceid);
    "type", `String i.entity_type;
    "title", `String (Title.to_string i.title);
    "age_days", `Int i.age_days;
  ]

let format_max_age = function
  | Service.Gc.Configured s -> s
  | Service.Gc.Default -> Service.Gc.default_max_age_display ^ " (default)"

let run dry_run set_max_age show_max_age json =
  let ctx = App_context.init () in
  Fun.protect ~finally:(fun () -> App_context.close ctx) (fun () ->
    let service = App_context.service ctx in
    if show_max_age then
      match Service.gc_get_max_age service with
      | Ok age ->
          let label = format_max_age age in
          if json then
            Common.print_json (`Assoc [
              "ok", `Bool true; "gc_max_age", `String label])
          else
            Printf.printf "GC max age: %s\n" label
      | Error err -> Common.exit_with_error ~json (Common.service_error_msg err)
    else match set_max_age with
    | Some age_str ->
        (match Service.gc_set_max_age service age_str with
        | Ok () ->
            if json then
              Common.print_json (`Assoc [
                "ok", `Bool true; "gc_max_age", `String age_str])
            else
              Printf.printf "GC max age set to: %s\n" age_str
        | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))
    | None ->
        if dry_run then
          match Service.gc_collect_with_config service with
          | Ok items ->
              if json then
                Common.print_json (`Assoc [
                  "ok", `Bool true;
                  "dry_run", `Bool true;
                  "items", `List (List.map gc_item_to_json items);
                ])
              else if items = [] then
                print_endline "Nothing to collect."
              else begin
                Printf.printf "Would remove %d item(s):\n" (List.length items);
                List.iter (fun (i : Service.Gc.gc_item) ->
                  let open Service.Gc in
                  Printf.printf "  %s %s %S (%dd old)\n"
                    i.entity_type (Identifier.to_string i.niceid)
                    (Title.to_string i.title) i.age_days
                ) items
              end
          | Error err -> Common.exit_with_error ~json (Common.service_error_msg err)
        else
          match Service.gc_run_with_config service with
          | Ok result ->
              let open Service.Gc in
              if result.items_removed > 0 then
                (match Service.flush service with Ok () -> () | Error _ -> ());
              if json then
                Common.print_json (`Assoc [
                  "ok", `Bool true;
                  "items_removed", `Int result.items_removed;
                  "relations_removed", `Int result.relations_removed;
                ])
              else
                Printf.printf "GC: removed %d item(s), %d relation(s).\n"
                  result.items_removed result.relations_removed
          | Error err -> Common.exit_with_error ~json (Common.service_error_msg err))

let dry_run_flag =
  let doc = "Show what would be removed without actually removing." in
  Arg.(value & flag & info [ "dry-run" ] ~doc)

let set_max_age_opt =
  let doc = "Set the GC max age threshold (e.g. 14d)." in
  Arg.(value & opt (some string) None & info [ "set-max-age" ] ~docv:"AGE" ~doc)

let show_max_age_flag =
  let doc = "Display the current GC max age setting." in
  Arg.(value & flag & info [ "show-max-age" ] ~doc)

let cmd_man = [
  `S "EXAMPLES";
  `P "Run garbage collection:";
  `P "  bs gc";
  `P "Dry-run (show what would be removed):";
  `P "  bs gc --dry-run";
  `P "Set GC max age to 14 days:";
  `P "  bs gc --set-max-age 14d";
  `P "Show current max age:";
  `P "  bs gc --show-max-age";
  `P "JSON output:";
  `P "  bs gc --json";
]

let cmd_info = Cmd.info "gc"
  ~doc:"Garbage-collect old terminal items from the knowledge base."
  ~man:cmd_man

let cmd =
  let term = Term.(const run $ dry_run_flag $ set_max_age_opt
                   $ show_max_age_flag $ Common.json_flag) in
  Cmd.v cmd_info term
