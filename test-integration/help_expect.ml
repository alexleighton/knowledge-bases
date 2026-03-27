module Helper = Test_helper

let contains_substring = Kbases.Data.String.contains_substring

let%expect_test "bs with no args shows help" =
  Helper.with_temp_dir (fun dir ->
    let result = Helper.run_bs ~dir [] in
    Printf.printf "exit: %d\n" result.exit_code;
    Printf.printf "has DESCRIPTION: %b\n"
      (contains_substring ~needle:"DESCRIPTION" result.stdout);
    Printf.printf "has COMMANDS: %b\n"
      (contains_substring ~needle:"COMMANDS" result.stdout);
    Printf.printf "has EXAMPLES: %b\n"
      (contains_substring ~needle:"EXAMPLES" result.stdout);
    Printf.printf "has description text: %b\n"
      (contains_substring ~needle:"Track todos" result.stdout);
    Printf.printf "stderr empty: %b\n"
      (result.stderr = ""));
  [%expect {|
    exit: 0
    has DESCRIPTION: true
    has COMMANDS: true
    has EXAMPLES: true
    has description text: true
    stderr empty: true
    |}]

let%expect_test "bs --help still works" =
  Helper.with_temp_dir (fun dir ->
    let result = Helper.run_bs ~dir ["--help"] in
    Printf.printf "exit: %d\n" result.exit_code;
    Printf.printf "has DESCRIPTION: %b\n"
      (contains_substring ~needle:"DESCRIPTION" result.stdout);
    Printf.printf "has COMMANDS: %b\n"
      (contains_substring ~needle:"COMMANDS" result.stdout);
    Printf.printf "has EXAMPLES: %b\n"
      (contains_substring ~needle:"EXAMPLES" result.stdout);
    Printf.printf "stderr empty: %b\n"
      (result.stderr = ""));
  [%expect {|
    exit: 0
    has DESCRIPTION: true
    has COMMANDS: true
    has EXAMPLES: true
    stderr empty: true
    |}]
