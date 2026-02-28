(**
   Git repository utilities.
*)

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

type exclude_result = Added | Already_present

let _contains_substring ~needle haystack =
  let nlen = String.length needle and hlen = String.length haystack in
  if nlen = 0 then true
  else if nlen > hlen then false
  else
    let rec loop i =
      if i > hlen - nlen then false
      else if String.sub haystack i nlen = needle then true
      else loop (i + 1)
    in
    loop 0

let add_exclude ~directory entry =
  let info_dir = Filename.concat (Filename.concat directory ".git") "info" in
  let exclude_path = Filename.concat info_dir "exclude" in
  if not (Sys.file_exists info_dir) then
    Unix.mkdir info_dir 0o755;
  let existing =
    if Sys.file_exists exclude_path then Io.read_file exclude_path
    else ""
  in
  if _contains_substring ~needle:entry existing then
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
