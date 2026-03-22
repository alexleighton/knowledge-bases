module Result = Kbases.Data.Result

let%expect_test "sequence collects oks" =
  let input = [ Ok 1; Ok 2; Ok 3 ] in
  Printf.printf "%s\n"
    (match Result.sequence input with
     | Ok ints ->
         ints
         |> List.map string_of_int
         |> String.concat ","
     | Error _ -> "error");
  [%expect {|1,2,3|}]

let%expect_test "sequence stops on first error" =
  let input = [ Ok "a"; Error "boom"; Ok "c" ] in
  Printf.printf "%s\n"
    (match Result.sequence input with
     | Ok _ -> "ok"
     | Error e -> e);
  [%expect {|boom|}]

let%expect_test "traverse collects oks" =
  let input = [ 1; 2; 3 ] in
  (match Result.traverse (fun x -> Ok (x * 10)) input with
   | Ok ints ->
       Printf.printf "%s\n"
         (ints |> List.map string_of_int |> String.concat ",")
   | Error _ -> print_endline "error");
  [%expect {|10,20,30|}]

let%expect_test "traverse short-circuits on first error" =
  let calls = ref 0 in
  let f x =
    incr calls;
    if x = 2 then Error "bang" else Ok (x * 10)
  in
  (match Result.traverse f [ 1; 2; 3 ] with
   | Ok _ -> print_endline "ok"
   | Error e -> Printf.printf "%s\n" e);
  Printf.printf "calls: %d\n" !calls;
  [%expect {|
    bang
    calls: 2
  |}]

let%expect_test "traverse on empty list" =
  (match Result.traverse (fun _ -> Error "boom") [] with
   | Ok l when l = [] -> print_endline "ok empty"
   | Ok _ -> print_endline "unexpected ok"
   | Error _ -> print_endline "unexpected error");
  [%expect {|ok empty|}]
