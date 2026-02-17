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
