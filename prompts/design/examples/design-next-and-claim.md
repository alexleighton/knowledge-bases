# Design: `next` and `claim` commands

## Problem Statement

An agent (or developer) using `bs` to track work currently has no direct way
to pick up the next piece of work. The workflow today is:

1. `bs list todo --status open` to see what's available.
2. Manually inspect dependencies (via `bs show`) to determine which todos are
   not blocked.
3. `bs update kb-N --status in-progress` to claim one.

This is tedious for humans and error-prone for agents, which must parse list
output, reason about dependency graphs, and issue a separate update. The
knowledge base already has the information needed to answer "what should I work
on next?" — open todos, `depends-on` relations, and todo statuses — but no
command exposes that reasoning.

Two new commands are needed: one that automatically selects the best available
todo (`next`), and one that claims a specific todo the caller has already
chosen (`claim`). Both transition the selected todo to `in-progress`.

A companion change: `bs list` needs an `--available` flag so callers can see
all claimable todos at once, not just the next one.

Additionally, the `depends-on` relation has a semantic consequence — it can
block a todo — but this is invisible in the current `show` output. When an
agent looks at a todo's relations, nothing indicates whether a dependency is
satisfied or still outstanding.

## Background

### CLI command structure

The `bs` binary registers 12 commands in `bin/main.ml` (53 lines) via
Cmdliner's `Cmd.group`. Each command lives in its own `cmd_*.ml` file (766
lines total across 12 files). Every command follows the same pattern:

1. A `run` function that initialises `App_context`, calls into
   `Kb_service`, and formats output.
2. Cmdliner `Arg` and `Term` definitions.
3. A `Cmd.v` that combines the two.

Resource management uses `Fun.protect` with `App_context.close` in the
`~finally` callback. Errors from the service layer are converted to strings
via `Common.service_error_msg` and printed to stderr with `Common.exit_with`,
which calls `exit 1`.

`cmdline_common.ml` (58 lines) provides shared infrastructure: `json_flag`,
`exit_with`, `print_json`, `resolve_content_source`, and the four relation
flags (`depends_on_opt`, `related_to_opt`, `uni_opt`, `bi_opt`).

New commands `next` and `claim` will follow this structure. The closest
existing analogues are `cmd_resolve.ml` (39 lines — single identifier,
validates entity type, transitions status, minimal output) and `cmd_show.ml`
(125 lines — identifier resolution, relation display, JSON formatting).

### Service layer

The service layer (`lib/service/`, 1659 lines across 22 files) is organised
as a facade pattern. `Kb_service` is the public entry point; it delegates to
five focused services:

| Module              | Responsibility                            |
|---------------------|-------------------------------------------|
| `Item_service`      | Identifier resolution (niceid or TypeId)  |
| `Query_service`     | `list`, `show`, `show_many`               |
| `Mutation_service`  | `update`, `resolve`, `archive`            |
| `Relation_service`  | `relate_many`, `build_specs`              |
| `Sync_service`      | JSONL flush/rebuild                       |

All write operations go through `Kb_service._with_flush`, which marks the
database dirty before the write and flushes to JSONL after. Transactions are
used for multi-step writes (`add_*_with_relations`, `relate`).

The shared error type is:

```ocaml
type error =
  | Repository_error of string
  | Validation_error of string
```

Every service module defines this same type (via `Item_service.error`) and
maps repository-level errors into it. The CLI never sees raw repository
errors.

### Identifier resolution

`Item_service.find` (`item_service.ml:73-83`) resolves a string identifier to
a `Todo_item` or `Note_item`. It first attempts to parse as a niceid; on
failure, it tries a TypeId. For niceids, it queries the todo repo first, then
the note repo. For TypeIds, it dispatches by prefix (`"todo"` or `"note"`).
This resolution is used by every command that accepts an `IDENTIFIER`
argument: `show`, `update`, `resolve`, `archive`, `relate`.

### Todo status and transitions

`Data.Todo` (`lib/data/todo.ml`, 57 lines) defines:

```ocaml
type status = Open | In_Progress | Done
```

Status transitions are unconstrained — any status can move to any other via
`Data.Todo.with_status`. The current codebase does not enforce a state
machine; `resolve` sets status to `Done` regardless of the current status.
`claim` will need to validate that the current status is `Open`.

### Relations and dependency semantics

`Data.Relation` (`lib/data/relation.ml`, 24 lines) is a simple record:

```ocaml
type t = {
  source        : Uuid.Typeid.t;
  target        : Uuid.Typeid.t;
  kind          : Relation_kind.t;
  bidirectional : bool;
}
```

The `depends-on` kind is a convention, not a distinguished type — it is a
`Relation_kind.t` with string value `"depends-on"` and `bidirectional =
false`. No code currently interprets the semantic meaning of `depends-on`.
The product requirements state that `depends-on` is an "ordering constraint
between todos: the source todo is blocked until the target todo is resolved,"
but this semantics is not enforced or surfaced anywhere in the codebase today.

`Repository.Relation` provides `find_by_source` and `find_by_target`, both
returning `Data.Relation.t list`. There is no query that joins relations with
entity status — to determine whether a dependency is blocking, one must fetch
the relations, then look up each target to check its type and status.

### `show` output and relation display

`Query_service.show` (`query_service.ml:124-153`) assembles a `show_result`
by:

1. Resolving the identifier to an item.
2. Querying `find_by_source` for outgoing relations.
3. Querying `find_by_target` for incoming relations.
4. For bidirectional relations found via `find_by_target`, moving them to
   the outgoing list (since both endpoints see them as outgoing).
5. Building `relation_entry` records with resolved niceid, entity type, and
   title for each related item.

The `relation_entry` type:

```ocaml
type relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
}
```

This type has no field for blocking status. Adding the `[blocking]`
annotation requires either extending `relation_entry` with an optional
boolean or computing it at the display layer in `cmd_show.ml`. Since blocking
depends on the target's status (which is already available when constructing
the entry via `Item_service.find`), the information is accessible during
assembly.

`cmd_show.ml` formats relation entries in `format_relation_entry` (line 31-36)
as a fixed four-column layout: `kind  niceid  type  title`. The `[blocking]`
tag would be appended as a fifth column. The JSON equivalent in
`relation_entry_to_json` (line 52-58) includes `kind`, `niceid`, `type`, and
`title`; a `blocking` boolean field would be added.

### `list` filtering

`Query_service.list` (`query_service.ml:48-99`) accepts `entity_type` and
`statuses` as string-level parameters, then:

1. When `entity_type` is `Some "todo"`, it parses statuses as
   `Data.Todo.status` values and queries `Repository.Todo.list`.
2. When `entity_type` is `None`, it partitions statuses by type
   (todo-valid vs note-valid) and queries both repos.
3. When statuses is empty, defaults apply: exclude `Done` todos and
   `Archived` notes.

`Repository.Todo.list` accepts a `statuses: Data.Todo.status list` parameter
and generates a SQL `WHERE status IN (...)` clause. When the list is empty, it
defaults to `WHERE status != 'done'`. Results are ordered by niceid.

Adding `--available` requires a different kind of filtering — not by status
column alone, but by the combination of status = Open and no unresolved
`depends-on` relations. This cannot be expressed as a single SQL query against
the `todo` table; it requires joining with the `relation` table or
post-filtering in the service layer. The existing `list` signature
(`~entity_type ~statuses`) does not accommodate this. A new parameter or a
separate code path will be needed.

### `resolve` as a structural model for `claim`

`Mutation_service.resolve` (`mutation_service.ml:45-56`) is the closest
existing analogue to `claim`:

```ocaml
let resolve t ~identifier =
  let open Item_service in
  let open Result.Syntax in
  let* item = find t.items ~identifier in
  match item with
  | Note_item note ->
      Error (Validation_error (...))
  | Todo_item todo ->
      let todo = Data.Todo.with_status todo Data.Todo.Done in
      TodoRepo.update t.todo_repo todo |> Result.map_error map_todo_repo_error
```

It resolves the identifier, rejects notes, transitions the status, and
persists. `claim` will follow the same shape but add two guards: the todo
must be `Open`, and it must have no unresolved `depends-on` relations. The
relation check requires access to `Repository.Relation`, which
`Mutation_service` does not currently hold — it only has `todo_repo`,
`note_repo`, and `items`.

### `next` selection logic

No existing service operation selects an item by computed criteria. All
current queries either resolve a specific identifier (`find`, `show`) or
return all items matching a status filter (`list`). `next` needs to:

1. Fetch all open todos (via `Repository.Todo.list ~statuses:[Open]`).
2. For each, fetch outgoing `depends-on` relations (via
   `Repository.Relation.find_by_source`).
3. For each dependency target that is a todo, check whether its status is
   `Done`.
4. Return the first todo (by niceid order) with no unresolved blocking
   dependencies.

This is an O(n * m) operation where n is open todos and m is average
dependency count. For the expected scale of knowledge bases (tens to low
hundreds of items), this is not a concern.

### Error handling patterns

The codebase uses two error strategies:

1. **Service errors** — `Repository_error of string | Validation_error of
   string`. All service functions return `(_, error) result`. The CLI maps
   both variants to a string via `Common.service_error_msg` and prints to
   stderr. Exit code is always 1 (via `Common.exit_with`).

2. **Data-layer validation** — `Invalid_argument` exceptions from smart
   constructors (e.g., `Relation_kind.make`, `Title.make`). These are caught
   at the service layer boundary and wrapped in `Validation_error`.

The requirements call for distinguished error types (`Not_a_todo`, `Not_open`,
`Blocked`, `Nothing_available`) that the CLI can format differently and that
`--json` error output can include as a machine-readable `reason` key.
Currently, errors are undistinguished strings — the only information is the
message text. The `resolve` command, for example, returns
`Validation_error "resolve applies only to todos, but kb-0 is a note"`.

To support structured JSON errors, the new commands will need either a richer
error type (a variant per failure mode) or a convention for encoding the
reason in the existing string error. The former is cleaner; it means `next`
and `claim` may need their own error type rather than reusing the shared
`Item_service.error`.

Note: the bin-layer convention (from `docs/bin/principles.md`) states that
"errors are not JSON-formatted — they go to stderr and the process exits
non-zero." The design requirement for JSON error output (`{"ok":false,
"reason":"blocked",...}`) would be a new pattern. Currently, `--json` only
affects success output.

### JSON output conventions

All commands follow a consistent pattern:

- Success JSON always includes `"ok": true` at the top level.
- `list` wraps results in `"items"`.
- `show` includes `outgoing` and `incoming` relation arrays.
- `resolve` returns `"action"`, `"type"`, and `"niceid"`.
- Serialization is inline in each `cmd_*.ml` file using `Yojson.Safe`
  polymorphic variants.

The design requirement for minimal JSON success output (`niceid` and `typeid`)
with `--show` expanding to the `show` shape fits this convention. The
`cmd_show.ml` module already exports `relation_entry_to_json` and
`item_to_json` (used by `cmd_add.ml` for `--json` output of relation results),
which can be reused.

### Exit code handling

`Common.exit_with` always calls `exit 1`. There is no mechanism for
distinguishing exit codes by error type. The design requires exit 0 for
"queue empty" from `next` and exit 123 for "queue stuck." This means `next`
cannot use `Common.exit_with` for the stuck case — it will need its own exit
logic, or `exit_with` will need to accept a code parameter.

Exit code 123 is already documented in the Cmdliner-generated man pages as
the code for "indiscriminate errors," and Cmdliner itself uses codes 124
(CLI parse error) and 125 (internal error). Using 123 for the stuck case is
consistent.

### Tests

**Unit tests** (`test/`, 3841 lines across 33 files) cover each layer:

- `test/service/query_service_expect.ml` (244 lines) — tests `list` and
  `show`, including relation display.
- `test/service/mutation_service_expect.ml` (215 lines) — tests `update`,
  `resolve`, `archive`.
- `test/service/relation_service_expect.ml` (287 lines) — tests relation
  creation and validation.

**Integration tests** (`test-integration/`, 2496 lines across 14 files):

- `show_expect.ml` (339 lines) — outgoing/incoming relations, JSON output,
  multi-show, auto-rebuild.
- `list_expect.ml` (214 lines) — type/status filtering, defaults, JSON.
- `resolve_expect.ml` (81 lines) — happy path, note rejection, JSON.
- `relate_expect.ml` (193 lines) — all relation types, duplicates, atomicity.
- `workflow_expect.ml` (282 lines) — cross-command scenarios.

All tests use `ppx_expect` with snapshot assertions. The test helper
(`test-integration/test_helper.ml`, 234 lines) provides `with_git_root`,
`run_bs`, `print_result` (normalises paths and TypeIds for determinism), and
JSON parsing utilities.

New commands will need:
- Unit tests in `test/service/` for the selection and claiming logic.
- Integration tests in `test-integration/` for `next`, `claim`, and the
  `--available` flag on `list`.
- Updates to `show_expect.ml` for the `[blocking]` annotation.

### Observations

1. **`Mutation_service` lacks relation access.** It holds `todo_repo`,
   `note_repo`, and `items`, but not `relation_repo`. `claim` needs to check
   dependencies, which requires querying relations. Either `Mutation_service`
   gains a `relation_repo` field, or `claim`/`next` live in a new service
   module that has access to both.

2. **`relation_entry` has no status information.** The type carries `kind`,
   `niceid`, `entity_type`, and `title` but not the target's status. The
   `[blocking]` annotation requires knowing whether the target is a non-done
   todo. This information is available during `show` assembly (the target item
   is resolved by `_entry_of_typeid`), but it is discarded. Either
   `relation_entry` gains a field, or the blocking computation happens
   separately.

3. **No JSON error output today.** The current convention sends errors to
   stderr as plain text and uses `--json` only for success. The design
   requires JSON-formatted error output with a `reason` key. This is a new
   pattern that will need a deliberate convention — either errors go to stdout
   as JSON when `--json` is passed (changing the stderr-only convention), or a
   new mechanism is introduced.

4. **`exit_with` is hardcoded to exit 1.** The design requires exit 0 for
   "queue empty" in `next`. This is not an error path at all — it is a
   successful non-action — so it bypasses `exit_with` entirely. The "queue
   stuck" case (exit 123) also cannot use `exit_with` as-is.

5. **`list` signature does not accommodate computed filters.** The current
   `list` function takes `~entity_type ~statuses`, both string-level
   parameters that map directly to SQL predicates. `--available` is a computed
   predicate that crosses tables. The implementation adds an `~available`
   parameter that short-circuits the normal dispatch when true.

6. **`show` relation assembly in `Query_service` already resolves target
   items.** The `_entry_of_typeid` helper calls `Item_service.find` for each
   relation target, which returns the full item including status. The blocking
   check (`depends-on` + target is a non-done todo) can be performed at this
   point with the information already in hand.

## Requirements

1. **`next` selects an available todo.** `bs next` picks the first open todo
   (by niceid order) that has no unresolved `depends-on` dependencies,
   transitions it to `in-progress`, and outputs a confirmation. A `depends-on`
   relation is unresolved when its target is a todo whose status is not `done`.
   A `depends-on` relation whose target is a note is never blocking — only
   todos can block other todos. — *Rationale: niceid order is deterministic
   and matches the user's mental model of the list; dependency resolution uses
   the existing `depends-on` semantics; notes have no completion lifecycle, so
   they cannot obstruct work.*

2. **`claim` transitions a specific todo.** `bs claim IDENTIFIER` takes a
   niceid or TypeId, validates that the target is an open, unblocked todo, and
   transitions it to `in-progress`. The same blocking rules from requirement 1
   apply. — *Rationale: agents sometimes know which todo they want; `claim`
   skips the selection step while enforcing the same guards.*

3. **`next` does not consider existing in-progress todos.** If other todos are
   already in-progress, `next` proceeds without warning. It selects from open
   todos only and is stateless about who is working on what. — *Rationale:
   assignment tracking is a separate concern; `next` manages the queue, not
   the workers.*

4. **Default output is a confirmation line.** Both commands print
   `Claimed todo: <niceid>  <title>` on success. — *Rationale: minimal,
   informative output suitable for both humans glancing at a terminal and
   agents parsing a known format.*

5. **`--show` flag displays full item details.** When passed, both commands
   print the same output as `bs show` for the claimed todo (including
   relations and blocking annotations) instead of the one-liner. — *Rationale:
   lets the agent immediately see the todo's content and context without a
   follow-up `bs show` call.*

6. **Distinguished error types.** Errors are not generic strings. Each failure
   mode has its own variant so callers (especially agents using `--json`) can
   distinguish between "not a todo", "not open", "blocked by dependencies",
   and "nothing available". — *Rationale: agents need to branch on failure
   reasons, not parse error messages. The existing shared `Item_service.error`
   type (`Repository_error | Validation_error`) is too coarse for this; `next`
   and `claim` will need their own error type with a variant per failure mode.*

   | Condition                        | Applies to | Error               |
   |----------------------------------|------------|---------------------|
   | Target is a note, not a todo     | `claim`    | `Not_a_todo`        |
   | Todo status is not `open`        | `claim`    | `Not_open`          |
   | Todo has unresolved dependencies | `claim`    | `Blocked`           |
   | No open unblocked todos exist    | `next`     | `Nothing_available` |

7. **Exit code semantics.** `next` exits 0 when no open unblocked todos exist
   (no work left is a success condition, not a failure). `next` exits non-zero
   (123) when open todos exist but all are blocked (work exists but none is
   available). `claim` errors exit non-zero (123). The "queue empty" case is
   not an error — it produces an informational message on stdout and exits 0.
   — *Rationale: agents use exit codes for control flow; "queue empty" and
   "queue stuck" are different situations requiring different responses. 123 is
   consistent with Cmdliner's convention for application errors.*

8. **`--json` support.** Both `next` and `claim` support `--json`, consistent
   with every other `bs` command. On success, default JSON output is minimal:
   niceid and TypeId, written to stdout. With `--show`, JSON output matches
   the `bs show --json` shape. When `--json` is passed and an error occurs,
   the error is written to stderr as a JSON object with `ok`, `reason`, and
   context fields (instead of the plain-text `Error: ...` format). This is a
   new convention — existing commands send plain-text errors to stderr
   regardless of `--json`. The new convention applies only to `next` and
   `claim` initially. — *Rationale: agents parsing `--json` need structured
   error information; stderr is the correct stream for errors so that stdout
   remains a clean success-only channel suitable for piping.*

9. **`--available` flag on `list`.** `bs list todo --available` shows all open
   todos with no unresolved `depends-on` dependencies — the same pool `next`
   selects from. `--available` and `--status` are mutually exclusive; passing
   both is a CLI error. `--available` implies both `open` status and `todo`
   type: `bs list --available` is equivalent to `bs list todo --available`.
   Passing `--available` with `note` type is a CLI error. — *Rationale: `next`
   gives you one item; `--available` lets you see the full set. Implemented as
   an `~available` parameter on the existing `list` function. The `available`
   branch short-circuits the normal entity_type/statuses dispatch, fetching
   open todos and filtering out blocked ones. This keeps listing as a single
   code path through the facade rather than adding a parallel entry point.*

10. **Blocking annotation on relation display.** Whenever relations are
    displayed (in `show` output and in `--show` output from `next`/`claim`),
    any `depends-on` relation whose target is a non-`done` todo is annotated
    as blocking. A `depends-on` relation whose target is a note is never
    annotated as blocking. In human-readable output the annotation appears as
    a `[blocking]` tag; in JSON output as a boolean field. This is a change
    to the existing `show` command's output — the `[blocking]` tag is additive
    (no existing output is removed or reordered). — *Rationale: makes
    dependency status visible at the point where the user is already looking at
    relations, without requiring a separate query. Codebase analysis confirmed
    that `Query_service.show` already resolves each relation target via
    `Item_service.find`, so the target's status is available during assembly
    without additional queries.*

11. **No transitive dependency resolution.** Blocking is evaluated on direct
    dependencies only. If A depends on B and B depends on C, A is blocked only
    if B is not done — the status of C is irrelevant to A's availability.
    Cycle detection is not attempted. — *Rationale: keeps the implementation
    simple and the behavior predictable; transitive resolution and cycle
    detection are graph-traversal problems that can be added later if needed.*

## Scenarios

### Scenario 1: Agent picks up work with `next`

Starting state: three open todos. `kb-1` depends on `kb-2` (which is open).
`kb-0` has no dependencies.

```
$ bs list todo --status open
kb-0  todo  open  Write unit tests for parser
kb-1  todo  open  Refactor parser module
kb-2  todo  open  Define error types
```

Agent runs:

```
$ bs next
Claimed todo: kb-0  Write unit tests for parser
```

`kb-0` was selected because it is the first (by niceid) open todo with no
unresolved dependencies. `kb-1` was skipped because it depends on `kb-2`,
which is not done.

```
$ bs show kb-0
todo kb-0 (todo_01abc...)
Status: in-progress
Title:  Write unit tests for parser

Add tests for the tokenizer edge cases.
```

### Scenario 2: Agent claims a specific todo

```
$ bs claim kb-2
Claimed todo: kb-2  Define error types
```

The agent chose `kb-2` directly. It was open and unblocked, so the claim
succeeded.

### Scenario 3: Claiming a blocked todo

`kb-1` depends on `kb-2`, which is still open.

```
$ bs claim kb-1
Error: kb-1 is blocked by: kb-2
```

With `--json` (written to stderr):

```json
{"ok":false,"reason":"blocked","niceid":"kb-1","blocked_by":["kb-2"]}
```

### Scenario 4: Claiming a non-open todo

```
$ bs claim kb-0
Error: kb-0 is already in-progress
```

### Scenario 5: No available work — queue empty

All todos are done or in-progress. No open todos remain.

```
$ bs next
No open unblocked todos
$ echo $?
0
```

This is a success (exit 0) — there is nothing left to do.

### Scenario 6: No available work — queue stuck

Open todos exist but all are blocked by unresolved dependencies.

```
$ bs next
Error: no available todos (1 open todo blocked)
$ echo $?
123
```

This is an error — work exists but cannot proceed.

### Scenario 7: `--show` flag

```
$ bs next --show
todo kb-2 (todo_01def...)
Status: in-progress
Title:  Define error types

Create a structured error type hierarchy for the parser.

Incoming:
  depends-on  kb-1  todo  Refactor parser module  [blocking]
```

The `[blocking]` tag on the incoming `depends-on` from `kb-1` indicates that
`kb-1` is not yet done and is therefore still blocked by this todo.

### Scenario 8: Blocking annotation in `show`

```
$ bs show kb-1
todo kb-1 (todo_01ghi...)
Status: open
Title:  Refactor parser module

Restructure the parser to use the new error types.

Outgoing:
  depends-on  kb-2  todo  Define error types  [blocking]
  related-to  kb-5  note  Parser design notes
```

The `[blocking]` tag appears on the `depends-on` to `kb-2` because `kb-2` is
not done. The `related-to` has no blocking annotation (it is not a
`depends-on` relation).

After `kb-2` is resolved:

```
$ bs resolve kb-2
$ bs show kb-1
...
Outgoing:
  depends-on  kb-2  todo  Define error types
  related-to  kb-5  note  Parser design notes
```

The `[blocking]` tag disappears because `kb-2` is now done.

### Scenario 9: `depends-on` targeting a note

`kb-3` depends on `kb-5`, which is a note.

```
$ bs show kb-3
todo kb-3 (todo_01xyz...)
Status: open
Title:  Implement caching layer

Design and implement request caching.

Outgoing:
  depends-on  kb-5  note  Cache design notes
```

No `[blocking]` tag appears — notes cannot block todos. `kb-3` is available
for `next` and `claim` despite the dependency on a note.

### Scenario 10: `list --available`

Starting state: `kb-0` has no dependencies. `kb-1` depends on `kb-2` (open).
`kb-2` has no dependencies. `kb-3` is in-progress.

```
$ bs list todo --available
kb-0  todo  open  Write unit tests for parser
kb-2  todo  open  Define error types
```

`kb-1` is excluded (blocked). `kb-3` is excluded (not open).

### Scenario 11: `--available` conflicts with `--status`

```
$ bs list todo --available --status open
Error: --available and --status are mutually exclusive
```

### Scenario 12: JSON success output

Default (minimal):

```
$ bs next --json
{"ok":true,"niceid":"kb-0","typeid":"todo_01abc..."}
```

With `--show`:

```
$ bs next --json --show
{"ok":true,"niceid":"kb-0","typeid":"todo_01abc...","status":"in-progress","title":"Write unit tests for parser","content":"Add tests for the tokenizer edge cases.","relations":[]}
```

The `--show` JSON shape matches `bs show --json`.

## Constraints

- Existing CLI commands must continue to work identically except where
  explicitly modified. `next`, `claim`, and `--available` are additive.
  The `show` command gains `[blocking]` annotations on `depends-on`
  relations — this is additive (no existing output removed or reordered).
- The on-disk formats (JSONL and SQLite schema) must not change. No new tables
  or fields are needed — blocking is computed from existing `depends-on`
  relations and todo statuses.
- No new runtime dependencies.
- `next` selection must be deterministic given the same knowledge base state.
- Both commands are non-interactive, consistent with the existing `bs`
  constraint that all input comes from arguments and stdin.
- Write operations (`next`, `claim`) must go through `Kb_service._with_flush`
  to maintain JSONL sync, consistent with all other write commands.

## Approaches

### Approach A: Extend existing services

Place `claim` and `next` in `Mutation_service`, `list_available` in
`Query_service`, and the blocking annotation in `Query_service.show`.
No new service modules — the new functionality distributes across the
two services that already own mutations and queries respectively.

**Mechanism**

*Mutation_service gains `relation_repo`.*  The `t` type adds a
`relation_repo` field so `claim` and `next` can check dependencies:

```ocaml
(* mutation_service.ml *)
type t = {
  items         : Item_service.t;
  todo_repo     : TodoRepo.t;
  note_repo     : NoteRepo.t;
  relation_repo : RelationRepo.t;   (* new *)
}

let init root = {
  items         = Item_service.init root;
  todo_repo     = Repository.Root.todo root;
  note_repo     = Repository.Root.note root;
  relation_repo = Repository.Root.relation root;  (* new *)
}
```

*`Data.Relation.is_dependency` predicate.*  The definition of "this
relation is a dependency" — `depends-on` kind and unidirectional — is
a property of the relation data, not of any particular service. A
predicate on `Data.Relation` centralizes this:

```ocaml
(* data/relation.ml *)
let is_dependency t =
  Relation_kind.equal (kind t) (Relation_kind.make "depends-on")
  && not (is_bidirectional t)
```

All blocking checks in both `Mutation_service` and `Query_service`
use this predicate instead of reimplementing the filter.

*Blocking check as a private helper.*  A helper in `Mutation_service`
determines whether a todo is blocked by unresolved dependencies:

```ocaml
let _is_blocked t todo =
  let open Result.Syntax in
  let typeid = Data.Todo.id todo in
  let* rels =
    RelationRepo.find_by_source t.relation_repo typeid
    |> Result.map_error map_relation_repo_error
  in
  let deps = List.filter Data.Relation.is_dependency rels in
  let rec check_blocking acc = function
    | [] -> Ok (List.rev acc)
    | rel :: rest ->
        let target_id = Data.Uuid.Typeid.to_string (Data.Relation.target rel) in
        match Item_service.find t.items ~identifier:target_id with
        | Ok (Item_service.Todo_item target_todo) ->
            if Data.Todo.status target_todo <> Data.Todo.Done then
              check_blocking (Data.Todo.niceid target_todo :: acc) rest
            else
              check_blocking acc rest
        | Ok (Item_service.Note_item _) | Error _ ->
            check_blocking acc rest
  in
  check_blocking [] deps
```

Returns `Ok []` when unblocked, `Ok [kb-2; kb-5; ...]` when blocked
(the niceids of the blocking todos).

*Distinguished error type for `claim`/`next`.*  These operations have
failure modes that don't map cleanly to the shared `Repository_error |
Validation_error` type. A local type captures the variants the CLI
needs:

```ocaml
(* mutation_service.ml *)
type claim_error =
  | Not_a_todo of string
  | Not_open of { niceid : string; status : string }
  | Blocked of { niceid : string; blocked_by : string list }
  | Nothing_available of { stuck_count : int }
  | Service_error of Item_service.error
```

`claim` and `next` return `(Data.Todo.t, claim_error) result` instead
of `(Data.Todo.t, Item_service.error) result`. The facade
(`Kb_service`) re-exports this type. The CLI maps each variant to the
appropriate output format and exit code.

*`claim` function:*

```ocaml
let claim t ~identifier =
  let open Result.Syntax in
  match Item_service.find t.items ~identifier with
  | Error e -> Error (Service_error e)
  | Ok (Item_service.Note_item note) ->
      Error (Not_a_todo (Data.Identifier.to_string (Data.Note.niceid note)))
  | Ok (Item_service.Todo_item todo) ->
      let niceid = Data.Identifier.to_string (Data.Todo.niceid todo) in
      if Data.Todo.status todo <> Data.Todo.Open then
        Error (Not_open { niceid; status = Data.Todo.status_to_string (Data.Todo.status todo) })
      else
        let* blockers = _is_blocked t todo |> Result.map_error (fun e -> Service_error e) in
        if blockers <> [] then
          Error (Blocked { niceid; blocked_by = List.map Data.Identifier.to_string blockers })
        else
          let todo = Data.Todo.with_status todo Data.Todo.In_Progress in
          TodoRepo.update t.todo_repo todo
          |> Result.map_error (fun e -> Service_error (map_todo_repo_error e))
```

*`next` function:*

```ocaml
let next t =
  let open Result.Syntax in
  let* todos =
    TodoRepo.list t.todo_repo ~statuses:[Data.Todo.Open]
    |> Result.map_error (fun e -> Service_error (map_todo_repo_error e))
  in
  let rec find_available stuck_count = function
    | [] ->
        if stuck_count = 0 then Ok None
        else Error (Nothing_available { stuck_count })
    | todo :: rest ->
        let* blockers = _is_blocked t todo |> Result.map_error (fun e -> Service_error e) in
        if blockers <> [] then find_available (stuck_count + 1) rest
        else
          let todo = Data.Todo.with_status todo Data.Todo.In_Progress in
          let* todo =
            TodoRepo.update t.todo_repo todo
            |> Result.map_error (fun e -> Service_error (map_todo_repo_error e))
          in
          Ok (Some todo)
  in
  find_available 0 todos
```

Returns `Ok None` for queue-empty (exit 0), `Ok (Some todo)` for
success, `Error (Nothing_available { stuck_count })` for queue-stuck
(exit 123).

*Blocking annotation in `Query_service.show`.*  `relation_entry` gains
an optional blocking field:

```ocaml
(* query_service.ml *)
type relation_entry = {
  kind        : Data.Relation_kind.t;
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  blocking    : bool option;   (* new — Some true/false for depends-on, None otherwise *)
}
```

`_entry_of_typeid` is extended to accept the resolved item's status
and compute blocking. Since the full item is already resolved via
`Item_service.find`, the status is available without additional
queries:

The helper receives the full `Data.Relation.t` (instead of just
`rel_kind`) so it can call `is_dependency`:

```ocaml
let _entry_of_typeid items rel direction =
  let typeid = match direction with
    | `Outgoing -> Data.Relation.target rel
    | `Incoming -> Data.Relation.source rel
  in
  let identifier = Data.Uuid.Typeid.to_string typeid in
  let is_dep = Data.Relation.is_dependency rel in
  match Item_service.find items ~identifier with
  | Ok (Todo_item t) ->
      let blocking =
        if is_dep then Some (Data.Todo.status t <> Data.Todo.Done)
        else None
      in
      Some { kind = Data.Relation.kind rel;
             niceid = Data.Todo.niceid t;
             entity_type = "todo";
             title = Data.Todo.title t;
             blocking }
  | Ok (Note_item n) ->
      Some { kind = Data.Relation.kind rel;
             niceid = Data.Note.niceid n;
             entity_type = "note";
             title = Data.Note.title n;
             blocking = if is_dep then Some false else None }
  | Error _ -> None
```

*`--available` integrated into `Query_service.list`:*  The existing
`list` function gains an optional `~available` parameter. When true,
it short-circuits the normal entity_type/statuses dispatch and
fetches open unblocked todos directly:

```ocaml
let _is_blocked_todo t ~dep_rels todo =
  let typeid_str = Data.Uuid.Typeid.to_string (Data.Todo.id todo) in
  List.exists (fun rel ->
    String.equal (Data.Uuid.Typeid.to_string (Data.Relation.source rel)) typeid_str
    && (let id = Data.Uuid.Typeid.to_string (Data.Relation.target rel) in
        match Item_service.find t.items ~identifier:id with
        | Ok (Todo_item t) -> Data.Todo.status t <> Data.Todo.Done
        | _ -> false)
  ) dep_rels

let list t ~entity_type ~statuses ?(available = false) () =
  if available then
    let open Result.Syntax in
    let* todos =
      fetch_todos [Data.Todo.Open]
    in
    let* all_rels =
      RelationRepo.list_all t.relation_repo
      |> Result.map_error _map_relation_repo_error
    in
    let dep_rels = List.filter Data.Relation.is_dependency all_rels in
    let items =
      List.filter (fun todo ->
        not (_is_blocked_todo t ~dep_rels todo)
      ) todos
      |> List.map (fun todo -> Todo_item todo)
    in
    Ok (sort_items items)
  else
    (* existing logic unchanged *)
```

The `available` branch ignores `entity_type` and `statuses` — the
CLI validates that `--available` is not combined with `--status` or
`note` type before calling. Uses `list_all` to fetch all relations in
a single query, then filters in-memory.

**What changes for consumers**

- `Mutation_service.init` takes the same `Repository.Root.t` argument
  but now extracts `relation_repo` from it. No call-site changes.
- `Kb_service` gains `claim` and `next` functions, re-exporting
  the `claim_error` type. The existing `list` gains an `~available`
  parameter. Two new `cmd_*.ml` files are added (`cmd_next.ml`,
  `cmd_claim.ml`). `cmd_list.ml` gains an `--available` flag.
- `relation_entry` gains a `blocking` field. Every consumer that
  constructs or pattern-matches on `relation_entry` must update:
  `cmd_show.ml` (display), `cmd_add.ml` (relation result display),
  and any test that constructs entries directly.
- `cmd_show.ml`'s `format_relation_entry` appends `  [blocking]` when
  `blocking = Some true`. `relation_entry_to_json` adds a `"blocking"`
  key when the field is `Some _`.

**What changes for tests**

- Existing `mutation_service_expect.ml` tests continue to pass — the
  `Mutation_service.t` type changes but `init` still takes the same
  argument.
- Existing `query_service_expect.ml` tests will need minor updates
  wherever `relation_entry` is constructed or matched, to include
  `blocking`.
- Existing `show_expect.ml` integration tests will see `[blocking]`
  appear on any `depends-on` relations where the target is a non-done
  todo — snapshot updates required.
- New unit tests for `_is_blocked`, `claim`, `next` in
  `mutation_service_expect.ml`.
- New unit tests for the `~available` branch of `list` in
  `query_service_expect.ml`.
- New integration tests: `next_expect.ml`, `claim_expect.ml`, and
  `list_expect.ml` updates for `--available`.

**Limitations**

- `Mutation_service` grows beyond its current scope of "apply a
  change to an identified item." `next` does selection, which is
  conceptually a query that happens to end with a mutation. This
  blurs the query/mutation separation the service layer currently
  maintains.
- The `available` branch of `list` wraps results in `Todo_item`
  internally, so the return type stays `item list`. This is consistent
  but means the branch ignores the `entity_type` and `statuses`
  parameters — the CLI must validate mutual exclusion before calling.

**Research needed**

All resolved — see Research section (R1–R3). Sketches updated to use
`Data.Relation.is_dependency` and string comparison for TypeId
equality.

---

### Approach B: New Workflow_service module

Extract all blocking-related logic into a new `Workflow_service`
module. This module owns `next`, `claim`, `list_available`, and the
`is_blocked` computation. `Query_service` calls into
`Workflow_service` for the blocking annotation in `show`.
`Mutation_service` is unchanged.

**Mechanism**

*New module with focused dependencies:*

```ocaml
(* workflow_service.ml *)
module TodoRepo = Repository.Todo
module RelationRepo = Repository.Relation

type t = {
  items         : Item_service.t;
  todo_repo     : TodoRepo.t;
  relation_repo : RelationRepo.t;
}

let init root = {
  items         = Item_service.init root;
  todo_repo     = Repository.Root.todo root;
  relation_repo = Repository.Root.relation root;
}
```

*Blocking check as a public function.*  Unlike Approach A's private
helper, `is_blocked` is part of the module's public interface so
`Query_service` can use it:

```ocaml
type blocker = {
  niceid : Data.Identifier.t;
}

let is_blocked t todo =
  let open Result.Syntax in
  let typeid = Data.Todo.id todo in
  let* rels =
    RelationRepo.find_by_source t.relation_repo typeid
    |> Result.map_error map_relation_repo_error
  in
  let deps = List.filter Data.Relation.is_dependency rels in
  let rec check acc = function
    | [] -> Ok (List.rev acc)
    | rel :: rest ->
        let target_id = Data.Uuid.Typeid.to_string (Data.Relation.target rel) in
        match Item_service.find t.items ~identifier:target_id with
        | Ok (Item_service.Todo_item target_todo) ->
            if Data.Todo.status target_todo <> Data.Todo.Done then
              check ({ niceid = Data.Todo.niceid target_todo } :: acc) rest
            else
              check acc rest
        | Ok (Item_service.Note_item _) | Error _ ->
            check acc rest
  in
  check [] deps
```

*`is_blocked_entry` for relation annotation.*  A second public
function computes blocking for a single relation entry, used by
`Query_service._entry_of_typeid`:

```ocaml
let is_blocking_relation t rel =
  if not (Data.Relation.is_dependency rel) then
    None
  else
    let id = Data.Uuid.Typeid.to_string (Data.Relation.target rel) in
    match Item_service.find t.items ~identifier:id with
    | Ok (Item_service.Todo_item todo) ->
        Some (Data.Todo.status todo <> Data.Todo.Done)
    | Ok (Item_service.Note_item _) -> Some false
    | Error _ -> None
```

Returns `None` for non-dependency relations, `Some true` for blocking
dependencies, `Some false` for resolved dependencies.

*Error type and `claim`/`next` are the same as Approach A* — the
`claim_error` type, `claim`, and `next` functions have the same shape,
just located in `Workflow_service` instead of `Mutation_service`.

*`--available` integration:* Same as Approach A — the `available`
branch is added to `Query_service.list`. `Workflow_service` does not
own listing; it focuses on the blocking computation and
`claim`/`next`.

*`Query_service` gains a `Workflow_service.t` dependency:*

```ocaml
(* query_service.ml *)
type t = {
  items         : Item_service.t;
  note_repo     : Note.t;
  todo_repo     : Todo.t;
  relation_repo : RelationRepo.t;
  workflow      : Workflow_service.t;  (* new *)
}
```

And `_entry_of_typeid` delegates to `Workflow_service`:

```ocaml
let _entry_of_typeid t rel direction =
  let typeid = match direction with
    | `Outgoing -> Data.Relation.target rel
    | `Incoming -> Data.Relation.source rel
  in
  let identifier = Data.Uuid.Typeid.to_string typeid in
  let blocking =
    Workflow_service.is_blocking_relation t.workflow rel
  in
  match Item_service.find t.items ~identifier with
  | Ok (Todo_item t) ->
      Some { kind = Data.Relation.kind rel;
             niceid = Data.Todo.niceid t;
             entity_type = "todo";
             title = Data.Todo.title t;
             blocking }
  | Ok (Note_item n) ->
      Some { kind = Data.Relation.kind rel;
             niceid = Data.Note.niceid n;
             entity_type = "note";
             title = Data.Note.title n;
             blocking }
  | Error _ -> None
```

**What changes for consumers**

- `Kb_service.t` gains a `workflow` field. `init` constructs a
  `Workflow_service.t` alongside the others.
- `Query_service.init` now takes a `Workflow_service.t` in addition
  to `Repository.Root.t`, or `Query_service.t` is extended to
  include it.
- Same CLI changes as Approach A: two new `cmd_*.ml` files, updated
  `cmd_list.ml`, updated `cmd_show.ml`.

**What changes for tests**

- `Query_service` tests need to construct a `Workflow_service.t` when
  setting up the service. This adds test setup boilerplate.
- `Mutation_service` tests are unchanged — `Mutation_service` is not
  modified.
- Same new test requirements as Approach A for `claim`, `next`,
  `list_available`, and blocking annotation.

**Limitations**

- Introduces a cross-service dependency: `Query_service` depends on
  `Workflow_service`. The current service layer has no inter-service
  dependencies — all services are peers initialized independently from
  `Repository.Root.t`. This changes that model. The dependency is
  one-directional and shallow (no cycles), but it is a structural
  precedent.
- `is_blocking_relation` duplicates the `Item_service.find` call that
  `_entry_of_typeid` also makes — the target item is resolved twice.
  This could be avoided by restructuring `_entry_of_typeid` to pass
  the resolved item to the blocking check, but that couples the two
  more tightly.
- The module adds 5 files (`.ml`, `.mli`, unit test, dune updates)
  for logic that is ~60 lines of implementation. The ceremony-to-logic
  ratio is high for what is fundamentally a simple computation.

**Research needed**

All resolved — see Research section (R1–R4). Sketches updated per
findings. The initialization order constraint (R4) is confirmed as
safe but is a structural cost unique to this approach.

## Research

### R1: `Typeid.equal` existence

`Data.Uuid.Typeid` (`typeid.mli`) exposes `make`, `to_string`,
`of_string`, `parse`, `of_guid`, `get_prefix`, and `get_suffix`.
There is no `equal` or `compare` function. Comparison requires
converting to string: `String.equal (Typeid.to_string a)
(Typeid.to_string b)`.

**Impact on approaches:** The `list_available` sketch in both
approaches must use string comparison for TypeId matching. The
`_is_blocked` helper already converts to string for
`Item_service.find`, so no additional conversion is needed there. This
is a minor ergonomic gap, not a blocker.

### R2: `TodoRepo.list` return type and ordering

`Repository.Todo.list` signature (`todo.mli:48-51`):

```ocaml
val list :
  t ->
  statuses:Data.Todo.status list ->
  (Data.Todo.t list, error) result
```

Returns `Data.Todo.t list`, ordered by niceid (the background section
confirms this, and the SQL uses `ORDER BY` on the niceid column).
Both approaches iterate this list directly — no wrapping needed at
the service level.

### R3: `Relation_kind` comparison

`Relation_kind` (`relation_kind.ml`) is an opaque `string` type with
a smart constructor. It exposes `equal : t -> t -> bool` (implemented
as `String.equal`) and `to_string`. There is no distinguished
`depends_on` value or `is_depends_on` predicate.

Two options for checking `depends-on`:
- `Relation_kind.equal kind (Relation_kind.make "depends-on")` — uses
  the module's own equality, but `make` validates the string each time
  (trivial cost).
- `Relation_kind.to_string kind = "depends-on"` — simpler, slightly
  less type-safe.

Both approaches should use `Relation_kind.equal`. Rather than each
service defining its own `_depends_on_kind` constant, the check is
encapsulated in `Data.Relation.is_dependency`:

```ocaml
(* data/relation.ml *)
let is_dependency t =
  Relation_kind.equal (kind t) (Relation_kind.make "depends-on")
  && not (is_bidirectional t)
```

**Impact on approaches:** All blocking-related filters use
`Data.Relation.is_dependency` instead of inline kind checks.
This centralizes the definition of what constitutes a dependency
relation in the data layer.

### R4: `Query_service.init` signature (Approach B only)

`Query_service.init` currently takes a single `Repository.Root.t`:

```ocaml
let init root = {
  items         = Item_service.init root;
  note_repo     = Repository.Root.note root;
  todo_repo     = Repository.Root.todo root;
  relation_repo = Repository.Root.relation root;
}
```

Approach B would need to change this to also accept a
`Workflow_service.t`. Since `Workflow_service.init` only needs
`Repository.Root.t`, there is no circular dependency — the
initialization order in `Kb_service.init` would be:

```ocaml
let workflow = Workflow_service.init root in
let query = Query_service.init root ~workflow in
```

This is safe but introduces an ordering constraint that doesn't exist
today. Currently all sub-services are initialized independently from
`root`. Approach B breaks this independence.

**Impact on Approach B:** This is a structural cost, not a blocker.
The alternative — having `Query_service` construct its own
`Workflow_service` internally — would create a second instance of the
service, which is wasteful but not incorrect (all state comes from
the shared `root`).

## Design Decisions

### D1: Distinguished error type for `claim`/`next`

The shared `Item_service.error` type (`Repository_error |
Validation_error`) is too coarse — every failure is an opaque string.
The new commands define a `claim_error` variant type with one
constructor per failure mode (`Not_a_todo`, `Not_open`, `Blocked`,
`Nothing_available`, `Service_error`). This lets the CLI map each
variant to a specific exit code and JSON `reason` key without parsing
error message text.

**Alternatives considered:**
- *Encode reason in the `Validation_error` string.* Matches the
  existing pattern but forces the CLI to parse strings for JSON error
  output — fragile and defeats the purpose of structured errors.
- *Extend the shared error type with new variants.* Would affect every
  command that handles errors, not just `next` and `claim`. The new
  variants are specific to workflow operations and don't belong in a
  type shared by `resolve`, `archive`, `update`, etc.

### D2: `next` returns `Ok None` for queue-empty, not an error

When no open todos exist, `next` returns `Ok None` (exit 0) rather
than an error. This aligns with the requirement that "no work left"
is a success condition — the agent should stop, not report a failure.
The "queue stuck" case (open todos exist but all are blocked) is the
error path, returning `Error (Nothing_available { stuck_count })`.

### D3: `--available` as a branch in existing `list`

`--available` is implemented as an `~available` parameter on the
existing `Query_service.list` function rather than a separate
`list_available` function. The existing `list` already has non-trivial
dispatch logic (entity type branching, status partitioning,
dual-repo queries). Adding one more branch for `available=true` fits
the existing pattern and avoids a parallel code path through the
facade. The CLI validates mutual exclusion with `--status` and `note`
type before calling.

### D4: `blocking` as `bool option` on `relation_entry`

The blocking annotation is modeled as `blocking : bool option` where
`None` means "not a depends-on relation" (no annotation), `Some true`
means "blocking" (unresolved dependency), and `Some false` means
"not blocking" (resolved dependency). This is preferred over a plain
`bool` because most relations are not `depends-on` and should not
carry a blocking annotation at all — `None` makes the absence of
the concept explicit rather than defaulting to `false`.

### D5: Bulk relation fetch for `list_available`

`list_available` uses `RelationRepo.list_all` to fetch all relations
in a single query, then filters in-memory, rather than issuing
per-todo `find_by_source` queries. This avoids N+1 queries. At the
expected scale (tens to hundreds of items), the performance difference
is negligible, but the single-query approach is simpler code — one
loop over a flat list rather than nested result-handling for each todo.

### D6: `is_dependency` predicate on `Data.Relation`

The definition of "this relation is a dependency" (`depends-on` kind,
unidirectional) is a property of the relation data. A predicate on
`Data.Relation` centralizes this, eliminating the need for each
service to independently filter by kind and bidirectionality. The
`Relation_kind.make "depends-on"` constant lives inside the
predicate's implementation, keeping it out of service-layer code.

## Rejected Alternatives

- **SQL-level blocking filter.** A single SQL query joining `todo`
  and `relation` tables could compute availability without
  application-level iteration. Rejected because the `depends-on`
  semantics depend on the *target's* status, requiring a self-join
  on the todo table through the relation table. This is feasible in
  SQL but adds query complexity for no practical gain at the expected
  scale, and the blocking rules (notes never block, only direct
  dependencies) are easier to express and verify in OCaml.

- **Blocking logic in `Item_service`.** Since `Item_service` is the
  shared dependency used by all services, placing `is_blocked` there
  would eliminate duplication. Rejected because `Item_service`
  currently has no access to `relation_repo` — it holds only
  `todo_repo` and `note_repo`. Adding `relation_repo` to
  `Item_service` would expand its scope from "identifier resolution"
  to "identifier resolution + property computation," and every service
  that constructs an `Item_service.t` would need to change.

## Consequences and Trade-offs

### Blocking predicate placement

The definition of "this relation is a dependency" (`depends-on` kind,
unidirectional) lives on `Data.Relation.is_dependency`. Both
approaches use this predicate, so neither duplicates the rule for
*identifying* a dependency. The remaining service-layer logic —
resolving the target item and checking its status — is inherently a
service concern and appears in both `_is_blocked` (for `claim`/`next`
guards) and `_entry_of_typeid` (for `show` annotation). These two
uses differ in shape: `_is_blocked` collects a list of blocking
niceids across all dependencies; `_entry_of_typeid` computes a
`bool option` for a single relation entry. The shared predicate on
`Data.Relation` eliminates the main duplication risk — a change to
what constitutes a dependency is made in one place.

### Service layer modularity

The current service layer has a clean property: all five services are
peers initialized independently from `Repository.Root.t`. No service
depends on another (except indirectly through `Item_service`, which
is an internal dependency used by construction, not by reference).

Approach A preserves this property. `Mutation_service` gains
`relation_repo` but remains a peer — it doesn't reference any other
service module.

Approach B breaks this property. `Query_service` would depend on
`Workflow_service`, introducing an initialization order constraint
and a structural precedent for inter-service dependencies. For a
codebase of this size, the precedent matters more than the
technical cost — once one cross-service dependency exists, more will
follow.

### Scope creep in `Mutation_service`

Approach A places `next` in `Mutation_service`, but `next` is really
a query-then-mutate operation — it selects from a computed set before
transitioning. This blurs the query/mutation separation. However,
`resolve` already lives in `Mutation_service` and is semantically
similar (find an item, validate it, transition its status). `next`
adds a selection step but follows the same pattern. The boundary was
never strict — `Mutation_service.update` already accepts an
identifier string and resolves it internally.

### Module count and ceremony

Approach B adds a new service module (~60 lines of logic) requiring
`.ml`, `.mli`, dune updates, and a unit test file. The
ceremony-to-logic ratio is high. Approach A distributes the same
logic across existing modules with no new files in the service layer.
Both approaches add the same CLI files (`cmd_next.ml`,
`cmd_claim.ml`) and integration tests.

## Requirement Coverage

Coverage analysis for the recommended approach (Approach A):

| # | Requirement | How satisfied |
|---|-------------|---------------|
| 1 | `next` selects an available todo | `Mutation_service.next` iterates open todos by niceid order, skipping blocked ones. First unblocked todo is transitioned to `in-progress`. |
| 2 | `claim` transitions a specific todo | `Mutation_service.claim` resolves identifier, validates open + unblocked, transitions to `in-progress`. |
| 3 | `next` ignores existing in-progress todos | `next` queries only `statuses:[Open]` — in-progress todos are never considered. |
| 4 | Default output is a confirmation line | CLI prints `Claimed todo: <niceid>  <title>` on success. |
| 5 | `--show` displays full item details | CLI calls `Kb_service.show` on the claimed todo's niceid and formats with `cmd_show.ml` helpers. |
| 6 | Distinguished error types | `claim_error` variant type with `Not_a_todo`, `Not_open`, `Blocked`, `Nothing_available`, `Service_error`. |
| 7 | Exit code semantics | `Ok None` → exit 0 (queue empty). `Error (Nothing_available _)` → exit 123. Other errors → exit 123. |
| 8 | `--json` support | Success: `{"ok":true,"niceid":...,"typeid":...}`. With `--show`: full show shape. Errors: `{"ok":false,"reason":...}` to stderr. |
| 9 | `--available` flag on `list` | `Query_service.list ~available:true` returns open unblocked todos. CLI adds `--available` flag, validates mutual exclusion with `--status`. |
| 10 | Blocking annotation on relation display | `relation_entry.blocking` field computed in `_entry_of_typeid`. `cmd_show.ml` renders `[blocking]` tag and JSON `blocking` field. |
| 11 | No transitive dependency resolution | `_is_blocked` checks only direct `depends-on` relations. No graph traversal. |

All requirements are fully satisfied. No compromises or partial coverage.

## Recommendation

**Approach A: Extend existing services.**

Approach A is the right choice because it preserves the service
layer's existing modularity (no inter-service dependencies), avoids
new module ceremony for a small amount of logic, and distributes
functionality into the modules that already own the relevant
concerns — mutations in `Mutation_service`, queries in
`Query_service`.

With `Data.Relation.is_dependency` centralizing the predicate, the
original duplication concern is resolved. The service-layer blocking
checks differ in shape (`_is_blocked` collects blockers;
`_entry_of_typeid` annotates a single entry) and share only the
target-status check, which is trivial and inherently tied to its
context.

**Fallback:** If blocking logic later grows complex enough to warrant
its own module (e.g., transitive resolution, cycle detection, priority
scoring), Approach B's `Workflow_service` can be extracted at that
point. Approach A is a valid stepping stone — the logic is already
factored into clear helper functions, making future extraction
straightforward.

**Future path:** Approach B becomes attractive if and when the
blocking computation grows beyond a simple per-relation check. The
current design explicitly avoids this complexity (requirement 11),
so Approach A is appropriate for the current scope.

## Open Questions

None — all questions resolved during requirements, research, and
synthesis.
