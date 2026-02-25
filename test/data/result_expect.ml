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
