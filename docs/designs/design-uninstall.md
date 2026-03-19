# Design: Uninstall command and init action refactor

## Problem Statement

`bs init` performs several independent side effects to set up a knowledge base:
creating a SQLite database, populating schema and config, installing a section
in AGENTS.md, and adding an exclude entry to `.git/info/exclude`. These actions
are currently implemented as a monolithic sequence in `Lifecycle.init_kb`. There
is no way to reverse them — a user who wants to remove a knowledge base must
manually identify and undo each step.

This creates two problems. First, there is no `uninstall` command: users who
want to cleanly remove a knowledge base have no supported path. Second, the
init actions are not individually testable or reusable — they are entangled in a
single function, making it difficult to verify each action's behavior in
isolation or to confirm that applying and then unapplying an action returns the
system to its original state.

The solution is to refactor init's side effects into a set of discrete,
reversible actions, then implement `uninstall` as the application of those same
actions in reverse.

## Background

### Architecture overview

The codebase has four layers with downward-only dependencies:

```
Service    → business operations          (lib/service/)
Repository → persistence (SQLite, JSONL)  (lib/repository/)
Control    → control flow, I/O            (lib/control/)
Data       → domain types, value objects   (lib/data/)
```

The CLI (`bin/`) is thin wiring on top of Service. Every command except `init`
opens an existing knowledge base through `App_context` → `Kb_service.open_kb()`.
Init bypasses `App_context` entirely — it calls `Kb_service.init_kb` directly,
which delegates to `Lifecycle.init_kb`.

### The init call chain

Init touches three modules across two layers:

- `bin/cmd_init.ml` — CLI argument parsing, output formatting
- `lib/service/lifecycle.ml` — orchestration: resolve dir/ns, create db,
  install files
- `lib/service/git.ml` — git repo detection, `.git/info/exclude` management

`Lifecycle.init_kb` performs five sequential steps:

1. **Resolve directory** — calls `Git.find_repo_root()` or validates an
   explicit `-d` path. Returns `Error (Validation_error _)` on failure.
2. **Resolve namespace** — validates an explicit `-n` value or derives one
   from the repo name. Returns `Error (Validation_error _)` on failure.
3. **Create the database** — calls `Root.init ~db_file ~namespace`, which
   opens a SQLite connection and creates five tables via `CREATE TABLE IF NOT
   EXISTS`. Guarded by `Sys.file_exists db_file`.
4. **Persist config** — writes `namespace` and optionally `gc_max_age` to
   the config table via `Config.set`.
5. **Install side-effect files** — two independent calls:
   `install_agents_md ~directory` and `install_git_exclude ~directory`.

Steps 3–5 run inside `Fun.protect ~finally:(fun () -> Root.close root)`.

The return type is:

```ocaml
type init_result = {
  directory   : string;
  namespace   : string;
  db_file     : string;
  agents_md   : agents_md_action;     (* Created | Appended | Already_present *)
  git_exclude : git_exclude_action;   (* Excluded | Already_excluded *)
}
```

### The five init actions in detail

**Action 1: Database creation.** `Root.init` opens a SQLite file and
initializes five repository modules, each running `CREATE TABLE IF NOT EXISTS`.
There is no corresponding teardown — `Root.close` calls `Sql.db_close` but does
not drop tables or delete the file. The database filename is the constant
`".kbases.db"`.

**Action 2: Config persistence.** Two `Config.set` calls write `"namespace"`
(always) and `"gc_max_age"` (when provided). Coupled to action 1 — operates on
the database it created. For uninstall, deleting the database file subsumes
this.

**Action 3: AGENTS.md installation.** `install_agents_md` has three branches:

- File does not exist → write `agents_md_template` → `Created`
- File exists, contains `agents_md_section_heading` → skip → `Already_present`
- File exists, does not contain heading → write
  `existing_contents ^ "\n" ^ agents_md_template` → `Appended`

The template is a 26-line string literal starting with `"## Knowledge Base\n"`.
Detection uses `Data.String.contains_substring` — not line-aware or
markdown-aware.

The append case writes `existing_contents ^ "\n" ^ agents_md_template` as the
new file contents. For uninstall to reverse this, it must find and remove the
substring `"\n" ^ agents_md_template` — i.e., the newline separator followed by
the full template text. The "exact match" case (file was created by init)
compares against `agents_md_template` alone, without the leading newline.

**Action 4: Git exclude entry.** `Git.add_exclude` ensures a line exists in
`.git/info/exclude`: creates the directory if missing, reads the existing file
(or empty string), checks for the entry via `contains_substring`, and appends
`entry ^ "\n"` (with a leading `"\n"` if the file doesn't end with one). The
entry value is `".kbases.db"`.

**Action 5: JSONL file.** Init does not create `.kbases.jsonl`. It is created
later by `Sync_service.flush` (triggered by the first mutating command). However,
uninstall must delete it because it will exist by the time a user wants to
uninstall.

### Observations

1. **Actions 1–2 are coupled; 3–4 are independent.** Database creation and
   config persistence are inherently sequential. AGENTS.md and git exclude are
   independent of each other and of the database. The action pattern needs to
   accommodate both.

2. **No file deletion in production code.** `Control.Io` provides `read_file`
   and `write_file` but no `delete_file`. `Sys.remove` is used only in test
   helpers. Uninstall will be the first command that deletes files.

3. **Substring matching is fragile for line removal.** Both `install_agents_md`
   and `Git.add_exclude` use `contains_substring` for detection. This works for
   presence checks but is insufficient for removal — the uninstall actions need
   line-level or exact-string-level operations.

4. **`cmd_init.ml` is the only command not routed through `App_context`.** Init
   calls `Service.init_kb` directly because there is no existing knowledge base
   to open. Uninstall shares this property — it operates on the filesystem, not
   on an open database handle.

5. **The `Kb_service` facade re-exports lifecycle types verbatim.** Adding new
   result types for uninstall follows the same pattern: define in `Lifecycle`,
   re-export in `Kb_service`, consume in `bin/cmd_uninstall.ml`.

6. **Init does not create the JSONL file.** The action pattern must handle the
   JSONL action that only has an unapply without a corresponding apply.

### Existing test coverage

- `lifecycle_expect.ml` (9 tests): covers `init_kb` success, rejection of
  non-git roots, invalid namespaces, re-initialization guard, `open_kb`
  scenarios.
- `git_expect.ml` (5 tests): covers `find_repo_root`, `is_git_root`,
  `repo_name`.
- `init_expect.ml` (11 integration tests): exercises `bs init` as a subprocess.
  Covers explicit dir/namespace, AGENTS.md create/append/idempotency, git
  exclude, gc-max-age, and JSON output.

There are no unit tests for `install_agents_md` or `install_git_exclude` in
isolation — they are only tested through `init_kb` or `bs init`. This is the
gap the refactor addresses.

## Requirements

### Action pattern

1. **Init's side effects are organized as four discrete actions:**

   - **Database file** — create `.kbases.db` (apply) / delete `.kbases.db`
     (unapply). Schema creation and config persistence are part of apply
     since they operate on the database and deleting the file subsumes them.
   - **JSONL file** — delete `.kbases.jsonl` (unapply only). Init does not
     create this file; it is produced by the first flush.
   - **AGENTS.md** — install section (apply) / remove section (unapply).
   - **Git exclude** — add `.kbases.db` entry (apply) / remove entry (unapply).

2. **Actions are individually testable.** Each action's apply and unapply can
   be tested in isolation. Roundtrip tests (apply then unapply returns to
   original state) must be possible for every action that has both directions.

3. **Actions report what they did.** Each action returns a result describing
   the outcome — whether it created, modified, skipped, or removed something.

4. **Actions are best-effort and independent.** If one action's precondition
   is not met (e.g., the file it would remove doesn't exist), it reports that
   and the remaining actions still execute.

### Init refactor

5. **Init uses the action pattern.** The existing `init` implementation is
   refactored to compose and apply actions rather than executing side effects
   inline. Init's observable behavior must not change. Existing tests must
   continue to pass without modification.

6. **Init's existing error cases are preserved.** Directory and namespace
   resolution remain orchestration-level preconditions, not actions.

### Uninstall command

7. **Uninstall requires `--yes`.** A bare `bs uninstall` (without the flag)
   must not perform any destructive action. Instead, it prints a message
   explaining that this command is destructive, not intended for agent use, and
   that `--yes` is required to proceed. The exit code is non-zero.

8. **Uninstall removes the SQLite database.** Deletes `.kbases.db` if it
   exists. Reports whether the file was deleted or was already absent.

9. **Uninstall removes the JSONL file.** Deletes `.kbases.jsonl` if it exists.
   The file is deleted from the filesystem only — uninstall does not run
   `git rm` or make any git commits. Reports whether the file was deleted or
   was already absent.

10. **Uninstall removes the AGENTS.md section using exact-string matching.**
    Four cases, checked in order:

    - File does not exist → report `not found`.
    - File contents exactly equal `agents_md_template` → delete the file
      → report `deleted`.
    - File contains the substring `"\n" ^ agents_md_template` (the appended
      form) → remove that substring → report `section removed`.
    - File contains `agents_md_section_heading` but neither exact match
      succeeded → report `section modified` (warning: the section appears to
      exist but has been edited since installation; manual removal needed).
    - None of the above → report `not found`.

    This approach uses the same `agents_md_template` constant that init uses,
    ensuring uninstall only removes text it recognizes. The `section_modified`
    warning uses the `agents_md_section_heading` constant for detection without
    attempting removal — if the user edited the section, automated removal is
    unsafe.

11. **Uninstall removes the git exclude entry.** Filters `.git/info/exclude`
    line by line, removing lines that match `".kbases.db"` exactly (after
    stripping the trailing newline). Leaves all other lines intact, including
    the file's trailing newline — if the original file ended with `'\n'`, the
    filtered file ends with `'\n'`. If no matching line exists or the exclude
    file does not exist, reports `not found`.

12. **Uninstall supports `--json` output.** Like init, uninstall reports the
    outcome of each action in both human-readable and JSON formats.

13. **Uninstall resolves the directory the same way as init.** Accepts `-d`
    to specify a git repository, or walks upward from cwd via
    `Git.find_repo_root()`. Reuses `resolve_directory` from Lifecycle. Unlike
    init, it does not validate that the database exists — partial teardown is
    supported by the best-effort property (requirement 4).

### Shared between commands

14. **Init and uninstall share action implementations where both directions
    exist.** The database file, AGENTS.md, and git exclude actions define
    both apply and unapply alongside each other. The JSONL deletion action is
    uninstall-only.

## Scenarios

### Scenario 1: Clean uninstall of a fully initialized knowledge base

Starting state: a git repository with a knowledge base initialized via
`bs init`. `.kbases.db`, `.kbases.jsonl`, and AGENTS.md all exist.
`.git/info/exclude` contains the `.kbases.db` entry.

```
$ bs uninstall --yes
Uninstalled knowledge base:
  Database:    /path/to/repo/.kbases.db (deleted)
  JSONL:       /path/to/repo/.kbases.jsonl (deleted)
  AGENTS.md:   /path/to/repo/AGENTS.md (deleted)
  Git exclude: /path/to/repo/.git/info/exclude (entry removed)
```

### Scenario 2: Uninstall when AGENTS.md has been edited

Starting state: AGENTS.md exists and contains the init-inserted section plus
additional user content. The section text is unmodified.

```
$ bs uninstall --yes
Uninstalled knowledge base:
  Database:    /path/to/repo/.kbases.db (deleted)
  JSONL:       /path/to/repo/.kbases.jsonl (deleted)
  AGENTS.md:   /path/to/repo/AGENTS.md (section removed)
  Git exclude: /path/to/repo/.git/info/exclude (entry removed)
```

After: AGENTS.md still exists but the `## Knowledge Base` section inserted by
init has been removed. The rest of the file is untouched.

### Scenario 3: Partial state — some artifacts already missing

Starting state: `.kbases.db` was manually deleted. AGENTS.md was never created.

```
$ bs uninstall --yes
Uninstalled knowledge base:
  Database:    /path/to/repo/.kbases.db (not found)
  JSONL:       /path/to/repo/.kbases.jsonl (deleted)
  AGENTS.md:   /path/to/repo/AGENTS.md (not found)
  Git exclude: /path/to/repo/.git/info/exclude (entry removed)
```

### Scenario 4: Roundtrip — init then uninstall restores original state

Starting state: a git repository with no knowledge base. AGENTS.md does not
exist. No mutating commands are run between init and uninstall.

```
$ bs init -n kb
Initialised knowledge base:
  Directory:   /path/to/repo
  Namespace:   kb
  Database:    /path/to/repo/.kbases.db
  AGENTS.md:   Created
  Git exclude: Excluded

$ bs uninstall --yes
Uninstalled knowledge base:
  Database:    /path/to/repo/.kbases.db (deleted)
  JSONL:       /path/to/repo/.kbases.jsonl (not found)
  AGENTS.md:   /path/to/repo/AGENTS.md (deleted)
  Git exclude: /path/to/repo/.git/info/exclude (entry removed)
```

After: the repository is in the same state as before `bs init`. The JSONL file
was never created (no mutating commands ran), so uninstall reports `not found`.

### Scenario 5: AGENTS.md section was edited after init

Starting state: AGENTS.md contains the `## Knowledge Base` heading but the
section body has been modified by the user.

```
$ bs uninstall --yes
Uninstalled knowledge base:
  Database:    /path/to/repo/.kbases.db (deleted)
  JSONL:       /path/to/repo/.kbases.jsonl (deleted)
  AGENTS.md:   /path/to/repo/AGENTS.md (section modified, manual removal needed)
  Git exclude: /path/to/repo/.git/info/exclude (entry removed)
```

The AGENTS.md file is left unchanged. The user must manually remove the modified
section.

### Scenario 6: Bare uninstall without flag

```
$ bs uninstall
Error: uninstall is destructive and not intended for agent use.
       It will remove the knowledge base database, JSONL file,
       AGENTS.md section, and git exclude entry.
       Pass --yes to proceed.
$ echo $?
1
```

No files are modified.

### Scenario 7: Uninstall outside a git repository

```
$ cd /tmp
$ bs uninstall --yes
Error: Not inside a git repository. Use -d to specify a directory.
$ echo $?
1
```

No files are modified. The error comes from `resolve_directory`, which is
shared with init.

### Scenario 8: JSON output

```
$ bs uninstall --yes --json
{
  "database": {"path": "/path/to/repo/.kbases.db", "action": "deleted"},
  "jsonl": {"path": "/path/to/repo/.kbases.jsonl", "action": "deleted"},
  "agents_md": {"path": "/path/to/repo/AGENTS.md", "action": "deleted"},
  "git_exclude": {"path": "/path/to/repo/.git/info/exclude", "action": "entry_removed"}
}
```

## Constraints

- **Init's observable behavior must not change.** Same files, same output, same
  errors, same exit codes. Existing unit tests (9) and integration tests (11)
  must continue to pass without modification.
- **No git operations.** Uninstall deletes files from the working tree only.
- **No new runtime dependencies.**
- **Existing CLI commands continue to work.**
- **New code follows project layering.** Action implementations belong in
  `lib/service/`. The CLI command belongs in `bin/cmd_uninstall.ml`. Result
  types defined in `Lifecycle` are re-exported through `Kb_service`.

## Design

Add `uninstall_*` functions alongside the existing `install_*` helpers in
`lifecycle.ml`. No new abstraction layer. Init stays structurally the same;
uninstall is a new function that calls the reverse helpers.

### Mechanism

The existing helpers already separate the AGENTS.md and git exclude logic into
named functions. The refactor extracts the database action into its own helper
too, then adds reverse counterparts:

```ocaml
(* --- Uninstall result types --- *)

type file_action = Deleted | Not_found
type agents_md_uninstall_action =
  | File_deleted | Section_removed | Section_modified | Not_found
type git_exclude_uninstall_action = Entry_removed | Entry_not_found

type uninstall_result = {
  directory    : string;
  database     : file_action;
  jsonl        : file_action;
  agents_md    : agents_md_uninstall_action;
  git_exclude  : git_exclude_uninstall_action;
}
```

Install helpers (existing, with `install_database` extracted from `init_kb`'s
inline code):

```ocaml
val install_agents_md    : directory:string -> agents_md_action
val install_git_exclude  : directory:string -> git_exclude_action
val install_database     :
  db_file:string -> namespace:string -> gc_max_age:string option ->
  (unit, error) result
```

Uninstall helpers:

```ocaml
val uninstall_file         : string -> file_action
val uninstall_agents_md    : directory:string -> agents_md_uninstall_action
val uninstall_git_exclude  : directory:string -> git_exclude_uninstall_action
```

`init_kb` calls the install helpers as it does today (the database creation
logic moves from inline code to `install_database`, but the call site and
control flow are unchanged):

```ocaml
let init_kb ~directory ~namespace ~gc_max_age =
  let open Result.Syntax in
  let* directory = resolve_directory directory in
  let* namespace = resolve_namespace ~directory namespace in
  let db_file = Filename.concat directory db_filename in
  if Sys.file_exists db_file then
    Error (Validation_error (Printf.sprintf "..."))
  else
    let* () = install_database ~db_file ~namespace ~gc_max_age in
    let agents_md = install_agents_md ~directory in
    let git_exclude = install_git_exclude ~directory in
    Ok { directory; namespace; db_file; agents_md; git_exclude }
```

`uninstall_kb` calls the reverse helpers:

```ocaml
let uninstall_kb ~directory =
  let open Result.Syntax in
  let* directory = resolve_directory directory in
  let database = uninstall_file (Filename.concat directory db_filename) in
  let jsonl = uninstall_file (Filename.concat directory jsonl_filename) in
  let agents_md = uninstall_agents_md ~directory in
  let git_exclude = uninstall_git_exclude ~directory in
  Ok { directory; database; jsonl; agents_md; git_exclude }
```

The uninstall helpers:

```ocaml
let uninstall_file path =
  if Sys.file_exists path then begin Sys.remove path; Deleted end
  else Not_found

let uninstall_agents_md ~directory =
  let path = Filename.concat directory agents_md_filename in
  if not (Sys.file_exists path) then Not_found
  else
    let contents = Io.read_file path in
    if contents = agents_md_template then begin
      Sys.remove path; File_deleted
    end else
      let appended_form = "\n" ^ agents_md_template in
      if Data.String.contains_substring ~needle:appended_form contents then
        let i = (* index of appended_form in contents *) in
        let before = String.sub contents 0 i in
        let after_end = i + String.length appended_form in
        let after = String.sub contents after_end
                      (String.length contents - after_end) in
        Io.write_file ~path ~contents:(before ^ after);
        Section_removed
      else if Data.String.contains_substring
                ~needle:agents_md_section_heading contents then
        Section_modified
      else Not_found

let uninstall_git_exclude ~directory =
  let exclude_path =
    Filename.concat directory ".git/info/exclude" in
  if not (Sys.file_exists exclude_path) then Entry_not_found
  else
    let contents = Io.read_file exclude_path in
    let lines = String.split_on_char '\n' contents in
    let filtered = List.filter (fun line -> line <> db_filename) lines in
    if List.length filtered = List.length lines then Entry_not_found
    else begin
      Io.write_file ~path:exclude_path
        ~contents:(String.concat "\n" filtered);
      Entry_removed
    end
```

Note on trailing-newline preservation in `uninstall_git_exclude`:
`String.split_on_char '\n'` on a file ending with `'\n'` produces a trailing
empty string `""` in the list. Since `"" <> db_filename`, the empty string
survives filtering, and `String.concat "\n"` reproduces the trailing newline.
If the file does not end with `'\n'`, no trailing empty string is produced and
no spurious newline is added. The file's trailing-newline state is preserved
in both cases.

### What changes for consumers

- `Lifecycle.mli` gains `uninstall_kb`, `uninstall_result`, and the new
  action types. `init_kb`'s signature and behavior are unchanged.
- `Kb_service` re-exports the new types and adds an `uninstall_kb` wrapper.
- `bin/cmd_uninstall.ml` is a new file, structured like `cmd_init.ml` —
  calls `Service.uninstall_kb`, formats the result.
- `bin/main.ml` adds the `uninstall` subcommand.

### What changes for tests

- Existing `lifecycle_expect.ml` tests pass unchanged — `init_kb`'s
  signature and behavior are identical.
- Existing `init_expect.ml` integration tests pass unchanged.
- New unit tests in `lifecycle_expect.ml` cover each `uninstall_*` helper in
  isolation and roundtrip (install then uninstall).
- New integration tests in `uninstall_expect.ml` cover the CLI scenarios.

### Limitations

- The pairing is by naming convention only. Nothing in the type system
  connects `install_agents_md` to `uninstall_agents_md`. Adding a new action
  requires the developer to remember to add both directions.
- The install and uninstall result types are separate (`agents_md_action` vs
  `agents_md_uninstall_action`). Each direction has its own vocabulary because
  the outcomes genuinely differ.

## Design Decisions

1. **Separate result types per direction.** Init outcomes (Created, Appended,
   Already_present) and uninstall outcomes (Deleted, Section_removed,
   Not_found) use different types rather than a shared enum. The operations
   produce genuinely different outcomes.

2. **Database creation stays as orchestration, not a pure action.** The
   database action's apply direction involves `Root.init`, five table
   creations, config persistence, and error handling. This is inherently
   sequential and stateful. The unapply direction (delete the file) is
   trivial and handled by `uninstall_file`.

3. **`resolve_directory` is shared.** Both init and uninstall reuse the
   existing `resolve_directory` helper.

4. **`--yes` is a gate, not a mode.** Checked in `cmd_uninstall.ml` before
   calling `Service.uninstall_kb`. The service layer always proceeds. This
   keeps the safety check in the CLI layer, following the pattern of `--force`
   on `cmd_delete.ml`.

5. **`Section_modified` warns without removing.** When the AGENTS.md heading
   is present but the exact template doesn't match, uninstall reports the
   discrepancy rather than attempting heuristic removal. The user is
   responsible for manual cleanup of content they modified.

## Rejected Alternatives

- **Functor-based action interface.** The codebase has no functors. The
  actions have different signatures (DB needs namespace and gc_max_age;
  AGENTS.md and git exclude need only directory; JSONL has no apply).
  Forcing uniform signatures adds complexity with no benefit.

- **Single polymorphic action type.** `type 'a action = { apply: 'a;
  unapply: 'a }` collapses when apply and unapply have different parameter
  lists and different result types. It also can't represent unapply-only
  actions.

- **Action modules in a dedicated directory.** Each action (AGENTS.md, git
  exclude, file deletion) gets its own module under `lib/service/action/`.
  This provides stronger isolation and per-module test files, but introduces
  9 new files for ~80 lines of extracted logic. It also requires relocating
  init's result types from `Lifecycle` to the action modules, causing
  mechanical updates to `Kb_service` re-exports and `cmd_init.ml` pattern
  matches — breaking the constraint that existing tests pass without
  modification. The isolation benefit doesn't justify the cost at the current
  scale of 4 actions. If the action count grows significantly, extraction
  into modules remains a straightforward follow-up.

## Recommendation

**Paired functions in `lifecycle.ml`.**

The uninstall helpers (`uninstall_file`, `uninstall_agents_md`,
`uninstall_git_exclude`) are added alongside the existing install helpers in
`lifecycle.ml`. No new abstraction layer, no type relocations, no changes to
existing tests. `lifecycle.ml` grows from ~193 to ~270 lines — well within the
size where a single file remains readable.

The trade-off is that install/uninstall pairing is by naming convention only.
This is acceptable at the current scale and can be revisited if the action count
grows.
