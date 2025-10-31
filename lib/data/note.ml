module CA = Control.Assert
module CE = Control.Exception

type t = {
  identifier : Identifier.t;
  title      : string;
  content    : string;
}
[@@deriving show]

let id      { identifier; _ } = identifier
let title   { title;      _ } = title
let content { content;    _ } = content

let _validate_title title =
  let len = String.length title in
  CA.require1 (len >= 1 && len <= 100)
    ~msg:"title must be between 1 and 100 characters, got %d" ~arg:len;
  title

let _validate_content content =
  let len = String.length content in
  CA.require1 (len >= 1 && len <= 10000)
    ~msg:"content must be between 1 and 10000 characters, got %d" ~arg:len;
  content

let make identifier title content = {
  identifier = identifier;
  title      = _validate_title title;
  content    = _validate_content content;
}
