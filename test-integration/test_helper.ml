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

let run_bs_with_pipe_stdin ~dir ?(timeout_s = 2.0) args =
  let exe = Lazy.force bs_exe in
  let stdout_file = Filename.temp_file "bs-out-" ".txt" in
  let stderr_file = Filename.temp_file "bs-err-" ".txt" in
  let pipe_r, pipe_w = Unix.pipe () in
  let stdout_fd = Unix.openfile stdout_file
    [O_WRONLY; O_CREAT; O_TRUNC] 0o644 in
  let stderr_fd = Unix.openfile stderr_file
    [O_WRONLY; O_CREAT; O_TRUNC] 0o644 in
  let env =
    Unix.environment ()
    |> Array.to_list
    |> List.filter (fun s ->
         not (String.length s >= 5
              && String.sub s 0 5 = "TERM="))
    |> (fun l -> l @ ["TERM=dumb"])
    |> Array.of_list
  in
  let pid = Unix.fork () in
  if pid = 0 then begin
    Unix.chdir dir;
    Unix.dup2 pipe_r Unix.stdin;
    Unix.close pipe_r;
    Unix.close pipe_w;
    Unix.dup2 stdout_fd Unix.stdout;
    Unix.close stdout_fd;
    Unix.dup2 stderr_fd Unix.stderr;
    Unix.close stderr_fd;
    Unix.execve exe (Array.of_list (exe :: args)) env
  end else begin
    Unix.close pipe_r;
    Unix.close stdout_fd;
    Unix.close stderr_fd;
    let deadline = Unix.gettimeofday () +. timeout_s in
    let rec wait () =
      match Unix.waitpid [WNOHANG] pid with
      | 0, _ ->
          if Unix.gettimeofday () >= deadline then begin
            Unix.kill pid Sys.sigkill;
            ignore (Unix.waitpid [] pid);
            Unix.close pipe_w;
            Sys.remove stdout_file;
            Sys.remove stderr_file;
            { exit_code = -1; stdout = ""; stderr = "TIMEOUT" }
          end else begin
            Unix.sleepf 0.01;
            wait ()
          end
      | _, Unix.WEXITED code ->
          Unix.close pipe_w;
          let read_and_cleanup f =
            let content = read_file f in Sys.remove f; content in
          { exit_code = code;
            stdout = read_and_cleanup stdout_file;
            stderr = read_and_cleanup stderr_file }
      | _, (Unix.WSIGNALED _ | Unix.WSTOPPED _) ->
          Unix.close pipe_w;
          Sys.remove stdout_file;
          Sys.remove stderr_file;
          { exit_code = -1; stdout = ""; stderr = "SIGNALED" }
    in
    wait ()
  end

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

let timestamp_re = Str.regexp "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] UTC"

let normalize_timestamps text =
  Str.global_replace timestamp_re "<TIMESTAMP>" text

let iso8601_re = Str.regexp "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z"

let normalize_iso8601 text =
  Str.global_replace iso8601_re "<ISO8601>" text

let print_result ~dir result =
  let norm text = text |> normalize_dir ~dir |> normalize_typeids
                       |> normalize_timestamps |> normalize_iso8601 in
  Printf.printf "[exit %d]\n" result.exit_code;
  if result.stdout <> "" then Printf.printf "%s" (norm result.stdout);
  if result.stderr <> "" then Printf.printf "STDERR: %s" (norm result.stderr)

let delete_db dir =
  let db = Filename.concat dir ".kbases.db" in
  if Sys.file_exists db then Sys.remove db

let init_kb dir =
  let result = run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"] in
  if result.exit_code <> 0 then
    failwith ("init_kb setup failed: " ^ result.stderr)

let parse_json stdout =
  try Yojson.Safe.from_string stdout
  with Yojson.Json_error msg ->
    Printf.printf "JSON parse error: %s\n" msg;
    `Null

let get_string json key =
  match json with
  | `Assoc pairs -> (
      match List.assoc_opt key pairs with
      | Some (`String s) -> s
      | _ -> "<missing>")
  | _ -> "<not-object>"

let get_bool json key =
  match json with
  | `Assoc pairs -> (
      match List.assoc_opt key pairs with
      | Some (`Bool b) -> b
      | _ -> false)
  | _ -> false

let get_int json key =
  match json with
  | `Assoc pairs -> (
      match List.assoc_opt key pairs with
      | Some (`Int n) -> n
      | _ -> -1)
  | _ -> -1

let get_list json key =
  match json with
  | `Assoc pairs -> (
      match List.assoc_opt key pairs with
      | Some (`List l) -> l
      | _ -> [])
  | _ -> []
