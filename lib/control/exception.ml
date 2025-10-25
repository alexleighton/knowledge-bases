
let invalid_arg1 fmt arg = invalid_arg (Format.sprintf fmt arg)

let invalid_arg2 fmt arg1 arg2 = invalid_arg (Format.sprintf fmt arg1 arg2)