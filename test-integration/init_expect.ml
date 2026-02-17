module Helper = Test_helper
module Root = Kbases.Repository.Root
module Config = Kbases.Repository.Config

let%expect_test "bs init with explicit directory and namespace" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Initialised knowledge base:
      Directory: <DIR>
      Namespace: kb
      Database:  <DIR>/.kbases.db
  |}]

let%expect_test "bs init creates database with correct namespace" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "test"]);
    let db_file = Filename.concat dir ".kbases.db" in
    Printf.printf "db exists: %b\n" (Sys.file_exists db_file);
    let real_db =
      Filename.concat
        (try Unix.realpath dir with Unix.Unix_error _ -> dir)
        ".kbases.db"
    in
    match Root.init ~db_file:real_db ~namespace:None with
    | Error (Root.Backend_failure msg) ->
        Printf.printf "open failed: %s\n" msg
    | Ok opened ->
        Fun.protect
          ~finally:(fun () -> Root.close opened)
          (fun () ->
            match Config.get (Root.config opened) "namespace" with
            | Ok ns -> Printf.printf "namespace: %s\n" ns
            | Error _ -> print_endline "namespace: not found"));
  [%expect {|
    db exists: true
    namespace: test
  |}]

let%expect_test "bs init resolves git root from cwd" =
  Helper.with_git_root (fun dir ->
    let nested = Filename.concat dir "subdir" in
    Unix.mkdir nested 0o755;
    let result = Helper.run_bs ~dir:nested ["init"; "-n"; "kb"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 0]
    Initialised knowledge base:
      Directory: <DIR>
      Namespace: kb
      Database:  <DIR>/.kbases.db
  |}]

let%expect_test "bs init in non-git directory fails" =
  Helper.with_temp_dir ~name:"kb-integ-no-git-" (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Directory is not a git repository root: <DIR>
  |}]

let%expect_test "bs init with invalid namespace fails" =
  Helper.with_git_root (fun dir ->
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "NOPE"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: namespace must match `^[a-z]+$`, got "NOPE"
  |}]

let%expect_test "bs init refuses re-initialisation" =
  Helper.with_git_root (fun dir ->
    ignore (Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"]);
    let result = Helper.run_bs ~dir ["init"; "-d"; dir; "-n"; "kb"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Knowledge base already initialised at <DIR>/.kbases.db.
  |}]

let%expect_test "bs init outside git repo with no args fails" =
  Helper.with_temp_dir ~name:"kb-integ-outside-" (fun dir ->
    let result = Helper.run_bs ~dir ["init"] in
    Helper.print_result ~dir result);
  [%expect {|
    [exit 1]
    STDERR: Error: Not inside a git repository. Use -d to specify a directory.
  |}]
