(**
   Git repository utilities.
*)

module Io = Control.Io

type exclude_result = Added | Already_present
type remove_exclude_result = Removed | Remove_not_found

let is_git_root dir =
  let git_path = Filename.concat dir ".git" in
  Sys.file_exists git_path

let find_repo_root ?start_dir () =
  let cwd = Sys.getcwd () in
  let start =
    match start_dir with
    | None -> cwd
    | Some dir ->
      if Filename.is_relative dir then Filename.concat cwd dir else dir
  in
  let rec search dir =
    if is_git_root dir then Some dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then None else search parent
  in
  search start

let repo_name path =
  let trimmed =
    if Filename.check_suffix path Filename.dir_sep && String.length path > 1 then
      String.sub path 0 (String.length path - 1)
    else
      path
  in
  Filename.basename trimmed

let add_exclude ~directory entry =
  let info_dir = Filename.concat (Filename.concat directory ".git") "info" in
  let exclude_path = Filename.concat info_dir "exclude" in
  if not (Sys.file_exists info_dir) then
    Unix.mkdir info_dir 0o755;
  let existing =
    if Sys.file_exists exclude_path then Io.read_file exclude_path
    else ""
  in
  if Data.String.contains_substring ~needle:entry existing then
    Already_present
  else begin
    let needs_newline =
      String.length existing > 0 && existing.[String.length existing - 1] <> '\n'
    in
    let new_contents =
      existing ^ (if needs_newline then "\n" else "") ^ entry ^ "\n"
    in
    Io.write_file ~path:exclude_path ~contents:new_contents;
    Added
  end

let remove_exclude ~directory entry =
  let info_dir = Filename.concat (Filename.concat directory ".git") "info" in
  let exclude_path = Filename.concat info_dir "exclude" in
  if not (Sys.file_exists exclude_path) then Remove_not_found
  else
    let contents = Io.read_file exclude_path in
    let lines = String.split_on_char '\n' contents in
    let filtered = List.filter (fun line -> line <> entry) lines in
    if List.length filtered = List.length lines then Remove_not_found
    else begin
      Io.write_file ~path:exclude_path ~contents:(String.concat "\n" filtered);
      Removed
    end
