module Helper = Test_helper

let contains_substring = Kbases.Data.String.contains_substring

let%expect_test "bs with no args shows help" =
  Helper.with_temp_dir (fun dir ->
    let result = Helper.run_bs ~dir [] in
    Printf.printf "exit: %d\n" result.exit_code;
    (if contains_substring ~needle:"DESCRIPTION" result.stdout
    then print_endline "has DESCRIPTION: true"
    else Printf.printf "has DESCRIPTION: false, stdout:\n%s\n" result.stdout);
    (if contains_substring ~needle:"COMMANDS" result.stdout
    then print_endline "has COMMANDS: true"
    else Printf.printf "has COMMANDS: false, stdout:\n%s\n" result.stdout);
    (if contains_substring ~needle:"EXAMPLES" result.stdout
    then print_endline "has EXAMPLES: true"
    else Printf.printf "has EXAMPLES: false, stdout:\n%s\n" result.stdout);
    (if contains_substring ~needle:"Track todos" result.stdout
    then print_endline "has description text: true"
    else Printf.printf "has description text: false, stdout:\n%s\n" result.stdout);
    if result.stderr = ""
    then print_endline "stderr empty: true"
    else Printf.printf "stderr empty: false, stderr:\n%s\n" result.stderr);
  [%expect {|
    exit: 0
    has DESCRIPTION: true
    has COMMANDS: true
    has EXAMPLES: true
    has description text: true
    stderr empty: true
    |}]

let%expect_test "bs --help prints usage with description, commands, and examples" =
  Helper.with_temp_dir (fun dir ->
    let result = Helper.run_bs ~dir ["--help"] in
    Printf.printf "exit: %d\n" result.exit_code;
    (if contains_substring ~needle:"DESCRIPTION" result.stdout
    then print_endline "has DESCRIPTION: true"
    else Printf.printf "has DESCRIPTION: false, stdout:\n%s\n" result.stdout);
    (if contains_substring ~needle:"COMMANDS" result.stdout
    then print_endline "has COMMANDS: true"
    else Printf.printf "has COMMANDS: false, stdout:\n%s\n" result.stdout);
    (if contains_substring ~needle:"EXAMPLES" result.stdout
    then print_endline "has EXAMPLES: true"
    else Printf.printf "has EXAMPLES: false, stdout:\n%s\n" result.stdout);
    if result.stderr = ""
    then print_endline "stderr empty: true"
    else Printf.printf "stderr empty: false, stderr:\n%s\n" result.stderr);
  [%expect {|
    exit: 0
    has DESCRIPTION: true
    has COMMANDS: true
    has EXAMPLES: true
    stderr empty: true
    |}]
