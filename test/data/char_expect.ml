module Char = Kbases.Data.Char

let%expect_test "ascii predicate matrix" =
  let cases = [ 'a'; 'z'; 'A'; 'Z'; '0'; '9'; 'f'; 'F'; 'g'; '#' ] in
  List.iter (fun c ->
    Printf.printf "'%c': lower=%b upper=%b letter=%b digit=%b hex=%b\n"
      c
      (Char.is_lowercase c)
      (Char.is_uppercase c)
      (Char.is_letter c)
      (Char.is_digit c)
      (Char.is_hex_digit c)
  ) cases;
  [%expect {|
    'a': lower=true upper=false letter=true digit=false hex=true
    'z': lower=true upper=false letter=true digit=false hex=false
    'A': lower=false upper=true letter=true digit=false hex=true
    'Z': lower=false upper=true letter=true digit=false hex=false
    '0': lower=false upper=false letter=false digit=true hex=true
    '9': lower=false upper=false letter=false digit=true hex=true
    'f': lower=true upper=false letter=true digit=false hex=true
    'F': lower=false upper=true letter=true digit=false hex=true
    'g': lower=true upper=false letter=true digit=false hex=false
    '#': lower=false upper=false letter=false digit=false hex=false
  |}]

