(** Utilities for integration tests that invoke the [bs] binary as a subprocess.

    {2 Environment normalisation}

    The subprocess is run with [TERM=dumb] to force cmdliner into its Plain
    formatting mode.  Cmdliner 2.x chooses between two error styles at startup
    based {e solely} on environment variables (it does not call [isatty]):

    - {b Ansi} (any [TERM] value other than ["dumb"]): values in error messages
      are rendered with ANSI bold escapes, e.g. [\x1b\[01mbanana\x1b\[m].
    - {b Plain} ([TERM] unset or ["dumb"], or [NO_COLOR] set): values are
      wrapped in single quotes, e.g. ['banana'].

    See [Cmdliner_base.Fmt.styler'] in the cmdliner source.  Because the
    subprocess inherits the caller's environment, a developer's [TERM=xterm-256color]
    would otherwise leak into the captured stderr and produce ANSI-escaped text
    that doesn't match the plain-text expect-test expectations. *)

type run_result = {
  exit_code : int;
  stdout : string;
  stderr : string;
}

let read_file path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let n = in_channel_length ic in
      really_input_string ic n)

let find_project_root () =
  let rec search dir =
    if Sys.file_exists (Filename.concat dir "dune-project") then dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then failwith "Cannot find project root (dune-project)"
      else search parent
  in
  search (Sys.getcwd ())

let bs_exe =
  lazy
    (let root = find_project_root () in
     let exe = Filename.concat root "_build/default/bin/main.exe" in
     if Sys.file_exists exe then exe
     else failwith ("bs executable not found at " ^ exe))

let rec rm_rf path =
  match Sys.file_exists path with
  | false -> ()
  | true ->
    if Sys.is_directory path then begin
      Array.iter
        (fun entry -> rm_rf (Filename.concat path entry))
        (Sys.readdir path);
      Unix.rmdir path
    end else
      Sys.remove path

let create_git_root ?(name = "kb-integ-") () =
  let dir = Filename.temp_dir name "" in
  Unix.mkdir (Filename.concat dir ".git") 0o755;
  dir

let with_git_root ?name f =
  let dir = create_git_root ?name () in
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f dir)

let with_temp_dir ?(name = "kb-integ-") f =
  let dir = Filename.temp_dir name "" in
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f dir)

let run_bs ~dir ?stdin args =
  let exe = Lazy.force bs_exe in
  let stdout_file = Filename.temp_file "bs-out-" ".txt" in
  let stderr_file = Filename.temp_file "bs-err-" ".txt" in
  let stdin_file, stdin_cleanup =
    match stdin with
    | None -> "/dev/null", Fun.id
    | Some content ->
        let f = Filename.temp_file "bs-in-" ".txt" in
        let oc = open_out f in
        output_string oc content;
        close_out oc;
        f, (fun () -> Sys.remove f)
  in
  let quoted_args = String.concat " " (List.map Filename.quote args) in
  let cmd =
    Printf.sprintf "cd %s && TERM=dumb %s %s <%s >%s 2>%s"
      (Filename.quote dir)
      (Filename.quote exe)
      quoted_args
      (Filename.quote stdin_file)
      (Filename.quote stdout_file)
      (Filename.quote stderr_file)
  in
  let exit_code = Sys.command cmd in
  stdin_cleanup ();
  let read_and_cleanup f =
    let content = read_file f in
    Sys.remove f;
    content
  in
  {
    exit_code;
    stdout = read_and_cleanup stdout_file;
    stderr = read_and_cleanup stderr_file;
  }

let normalize_dir ~dir text =
  let real_dir =
    try Unix.realpath dir with
    | Unix.Unix_error _ -> dir
  in
  let result = Str.global_replace (Str.regexp_string real_dir) "<DIR>" text in
  if real_dir <> dir then
    Str.global_replace (Str.regexp_string dir) "<DIR>" result
  else result

let typeid_re = Str.regexp "[a-z][a-z_]*_[0-9a-hjkmnp-tv-z]+"

let normalize_typeids text =
  Str.global_replace typeid_re "<TYPEID>" text

let print_result ~dir result =
  let norm text = text |> normalize_dir ~dir |> normalize_typeids in
  Printf.printf "[exit %d]\n" result.exit_code;
  if result.stdout <> "" then Printf.printf "%s" (norm result.stdout);
  if result.stderr <> "" then Printf.printf "STDERR: %s" (norm result.stderr)

let init_kb dir =
  let result = run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"] in
  if result.exit_code <> 0 then
    failwith ("init_kb setup failed: " ^ result.stderr)
