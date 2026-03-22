# Design: Multi-identifier support for batch state-transition commands

## Problem Statement

Several `bs` commands that transition item state — `resolve`, `close`,
`archive`, and `reopen` — accept only a single identifier per invocation. When
an agent or user finishes a batch of work and wants to resolve three todos and
archive two notes, they must run five separate commands. Each command
independently opens the database, performs one operation, and closes it.

This friction is unnecessary. The `delete` and `show` commands already accept
variadic identifiers (`bs delete kb-0 kb-1 kb-2`, `bs show kb-0 kb-1`),
demonstrating that the CLI infrastructure, argument parsing, and JSON output
patterns for multi-identifier commands already exist.

The gap also extends to documentation. The AGENTS.md template injected by
`bs init` shows only single-identifier examples for lifecycle commands, and
does not demonstrate multi-target relation creation — even though `relate`
already supports `--depends-on kb-1 --depends-on kb-2` in a single invocation.
Agents that consume AGENTS.md as their primary interface reference will not
discover these capabilities without explicit examples.

## Background

### Architecture overview

The codebase has four layers with downward-only dependencies:

```
bin/       → CLI argument parsing, output formatting   (21 files, 1607 lines)
Service    → business operations                       (lib/service/)
Repository → persistence (SQLite, JSONL)               (lib/repository/)
Data       → domain types, value objects                (lib/data/)
```

The CLI is thin wiring: each `cmd_*.ml` file parses arguments via Cmdliner,
calls a Service function, and formats the result. Unit tests cover `lib/`;
integration tests (`test-integration/`, 26 files) exercise `bin/` as
subprocesses.

### How state transitions work today

All three single-ID mutation commands — `resolve`, `archive`, `reopen` — follow
the same call chain:

1. **bin layer** (`cmd_resolve.ml`, `cmd_archive.ml`, `cmd_reopen.ml`): parses
   a single `IDENTIFIER` positional arg, calls `Service.resolve` /
   `Service.archive` / `Service.reopen`, formats the result or error.

2. **`Kb_service`** (`kb_service.ml:192–202`): wraps each call in
   `_with_flush`, which marks sync dirty before the mutation and flushes to
   JSONL after. Delegates to `Mutation.*`.

3. **`Mutation_service`** (`mutation_service.ml`): `resolve` and `archive`
   both use a shared `_transition_to` helper (line 68) that finds the item via
   `Item_service.find`, validates entity type (todo vs note), then calls
   `update` with the target status string. `reopen` (line 141) does its own
   find-and-match because it must inspect the current status of either entity
   type to validate terminal state, then routes to `update` with `"open"` or
   `"active"`.

The return types differ across the three operations:

- `resolve : t -> identifier:string -> (Data.Todo.t, error) result`
- `archive : t -> identifier:string -> (Data.Note.t, error) result`
- `reopen  : t -> identifier:string -> (item, error) result`

`resolve` returns `Todo.t`, `archive` returns `Note.t`, `reopen` returns the
polymorphic `item` (either `Todo_item` or `Note_item`). All three use the same
error type: `Item_service.error` (`Repository_error | Validation_error`).

### The multi-ID reference: `delete` and `show`

Two commands already accept variadic identifiers. They establish the patterns
a multi-ID implementation should follow.

**`delete`** uses a two-phase approach in `Delete_service.delete_many`
(lines 113–138):

- *Phase 1*: maps each identifier through `Item_service.find` and blocking
  checks, collecting `Ok item` results. `Data.Result.sequence` (a
  `('a, 'e) result list -> ('a list, 'e) result` combinator in
  `lib/data/result.mli`) short-circuits on the first error.
- *Phase 2*: only runs if Phase 1 succeeds. Deletes all resolved items.

At the `Kb_service` level (lines 222–227), `delete_many` wraps both phases
in a single `_with_flush_map` and a single `Repository.Sqlite.with_transaction`,
giving the whole operation one flush and one transaction boundary.

In the bin layer, `cmd_delete.ml` dispatches: single ID calls `Service.delete`
(result wrapped in a singleton list), multiple IDs call `Service.delete_many`.
Both paths produce the same output shape — `List.iter` for text,
`"deleted": [...]` array for JSON.

**`show`** takes a simpler approach in `Show_service.show_many` (lines 95–103):
a tail-recursive fold that calls `show` per identifier, failing on the first
error. No separate dispatch — `cmd_show.ml` always calls `show_many`,
even for a single ID.

### Positional argument parsing

Multi-ID commands use a Cmdliner pattern with two argument definitions:

```ocaml
let first_identifier_arg =
  Arg.(required & pos 0 (some string) None & info [] ~docv:"IDENTIFIER" ~doc)
let rest_identifiers_arg =
  Arg.(value & pos_right 0 string [] & info [] ~docv:"IDENTIFIER")
```

The `run` function receives both and conses them: `first :: rest`. This ensures
at least one identifier is always required. Single-ID commands use only
`Arg.(required & pos 0 ...)`.

### The `close` alias

`cmd_close.ml` (22 lines) defines its own `identifier_arg` and `cmd_man` but
delegates to `Cmd_resolve.run` via `Term.(const Cmd_resolve.run ...)`. Any
change to `Cmd_resolve.run`'s signature (e.g. adding `rest_identifiers`) must
be mirrored in `cmd_close.ml`'s Term wiring.

### Flush and transaction boundaries

Mutation operations that don't touch multiple entities (`resolve`, `archive`,
`reopen`) are wrapped in `_with_flush` but not in an explicit transaction —
they perform a single `UPDATE` via the repository. `delete` and
`delete_many`, which cascade across relations, niceids, and entities, use
`Repository.Sqlite.with_transaction` inside `_with_flush_map`. Multi-ID
mutations that perform multiple independent UPDATEs will need to decide
whether to wrap in a transaction for atomicity.

### AGENTS.md template

The template is a string literal `agents_md_template` in `lifecycle.ml`
(lines 12–37). It contains a fenced code block with example commands. The
current lifecycle examples are:

```
# Complete and archive
bs resolve kb-0
bs archive kb-5
```

And the relation example is:

```
bs relate kb-2 --related-to kb-3
```

The template is injected once at `bs init` — either as a new file or appended
to an existing AGENTS.md. `uninstall` reverses the injection by exact string
match. Changes to the template therefore affect only newly initialized
knowledge bases and must preserve the uninstall round-trip (the template string
is used for both injection and removal matching).

### Root help text

`main.ml` (lines 31–59) defines the root `EXAMPLES` section with a single
`relate` example (`bs relate kb-2 --related-to kb-3`) and single-ID lifecycle
examples (`bs resolve kb-0`, `bs archive kb-1`). The `show` example already
demonstrates multi-ID: `bs show kb-0 kb-1`.

### Existing test coverage

Integration tests for the affected commands:

| Command   | File                      | Lines | Tests | Multi-ID? |
|-----------|---------------------------|-------|-------|-----------|
| `delete`  | `delete_expect.ml`        | 112   | 7     | Yes       |
| `show`    | `show_json_expect.ml`     | 137   | 6     | Yes       |
| `show`    | `show_basic_expect.ml`    | 150   | 10    | No        |
| `resolve` | `resolve_expect.ml`       | 130   | 8     | No        |
| `archive` | `archive_expect.ml`       | 130   | 8     | No        |
| `reopen`  | `reopen_expect.ml`        | 119   | 7     | No        |
| `close`   | `close_expect.ml`         | 83    | 6     | No        |

Service unit tests: `delete_service_expect.ml` has a `delete_many` test
(atomic failure); `mutation_service_resolve_expect.ml` (5 tests) and
`mutation_service_reopen_expect.ml` (5 tests) cover single-ID only. There is
no `mutation_service_archive_expect.ml` — archive's service-level behavior is
covered only through integration tests.

### Observations

1. **`resolve` and `archive` can reuse `_transition_to` for multi-ID.**
   Both single-ID functions already delegate to the `_transition_to` helper,
   which calls `Item_service.find` and then `update`. A `*_many` variant can
   map identifiers through the same helper with `Data.Result.sequence` for
   Phase 1, matching the `delete_many` pattern. No new validation logic is
   needed.

2. **`reopen` has inline validation that complicates extraction.** Unlike
   `resolve`/`archive`, `reopen` does not use `_transition_to` — it has
   entity-type-specific matching with custom error messages for non-terminal
   states. A `reopen_many` that reuses the existing `reopen` body (as
   `show_many` reuses `show`) avoids duplicating this logic but makes
   two-phase separation less clean: each `reopen` call performs its own find
   *and* update. The alternative is to split `reopen` into validate + execute
   phases.

3. **Transaction boundaries differ between delete and mutation operations.**
   `delete_many` runs inside `with_transaction` because it cascades across
   three tables per item. The mutation operations do a single `UPDATE` per
   item. Whether multi-ID mutations need a transaction depends on the atomicity
   requirement: without one, a crash mid-batch could leave some items
   transitioned and others not, even though validation passed.

4. **`_with_flush` is called once per `Kb_service` entry point.** Multi-ID
   operations need exactly one flush wrapping the entire batch, not one per
   item. This means the `*_many` functions must live at the `Mutation_service`
   level (inside a single `_with_flush` call from `Kb_service`), not be
   composed by calling `Kb_service.resolve` in a loop from bin.

5. **Return type asymmetry.** `resolve` returns `Todo.t`, `archive` returns
   `Note.t`, but `reopen` returns the polymorphic `item`. A `resolve_many`
   returning `Todo.t list` and `archive_many` returning `Note.t list` are
   natural. A uniform `*_many` that works across all three would need `item`
   as the return type, losing the type-level guarantee that `resolve` only
   produces todos.

6. **The `close` alias must track `resolve`'s signature.** `cmd_close.ml`
   calls `Cmd_resolve.run` directly. When `run`'s parameter list changes from
   `identifier json` to `first_identifier rest_identifiers json`, the
   `cmd_close.ml` Term must wire the same two positional arguments. This is
   mechanical but easy to forget.

7. **JSON shape change is observable in integration tests.** The current
   `resolve_expect.ml` and `archive_expect.ml` test JSON output with the flat
   `{"ok":true,"action":"resolved",...}` shape. These tests must be updated to
   expect the new array-wrapped shape, which will make the breaking change
   visible in the diff.

8. **`show` already uses the uniform approach.** `cmd_show.ml` always calls
   `show_many` regardless of identifier count, avoiding the
   single-vs-multi dispatch in `cmd_delete.ml`. This is the simpler pattern
   and could be followed by the mutation commands, though it requires
   `*_many` service functions to exist even for single-ID calls.

## Requirements

1. **`resolve` accepts multiple identifiers.** `bs resolve kb-0 kb-1 kb-2`
   resolves all three todos in a single invocation. The existing single-ID
   form (`bs resolve kb-0`) continues to work unchanged.

2. **`close` accepts multiple identifiers.** `close` is an alias for
   `resolve` and must gain the same multi-ID support. `cmd_close.ml`
   delegates to `Cmd_resolve.run` and must wire the same two positional
   arguments (`first_identifier_arg`, `rest_identifiers_arg`) that
   `cmd_resolve.ml` uses.

3. **`archive` accepts multiple identifiers.** `bs archive kb-1 kb-2`
   archives both notes in a single invocation.

4. **`reopen` accepts multiple identifiers.** `bs reopen kb-3 kb-4` reopens
   both items in a single invocation. `reopen` operates on both todos and
   notes, so a single invocation may reopen a mix of entity types.

5. **Atomic error semantics.** When given multiple identifiers, the command
   validates all identifiers before performing any state transitions. If any
   identifier is invalid, not found, or in an incompatible state, the entire
   operation fails with no items modified — matching the two-phase
   validate-then-execute pattern used by `delete_many`. Multi-ID mutations
   must be wrapped in `Repository.Sqlite.with_transaction` at the
   `Kb_service` level, matching `delete_many`'s transaction boundary.
   *Refined after codebase analysis: single-ID mutations perform one UPDATE
   and skip explicit transactions; multi-ID mutations perform multiple
   independent UPDATEs and need a transaction to guarantee atomicity.*

6. **Service layer exposes `*_many` variants in `Mutation_service`.** Each
   affected operation gets a corresponding function (`resolve_many`,
   `archive_many`, `reopen_many`) that accepts a list of identifiers and
   returns a list of results on success. These live in `Mutation_service`,
   not `Kb_service`, and are wrapped in a single `_with_flush` call by
   `Kb_service`. The single-ID service functions remain unchanged.
   *Refined after codebase analysis: `_with_flush` is called once per
   `Kb_service` entry point, so `*_many` must live at the `Mutation_service`
   level to avoid multiple flushes per batch.*

7. **JSON output uses action-specific array keys.** Multi-ID JSON output is
   a single object with `"ok": true` and an array field containing per-item
   results. The array key matches the action: `"resolved"`, `"archived"`,
   `"reopened"` — consistent with `delete`'s `"deleted"` key. Example for
   resolve:
   ```json
   {
     "ok": true,
     "resolved": [
       { "type": "todo", "niceid": "kb-0" },
       { "type": "todo", "niceid": "kb-1" }
     ]
   }
   ```
   Single-ID invocations produce the same array-wrapped shape (an array of
   one) to keep the output schema uniform for consumers. This is a breaking
   change from the current flat-object single-ID JSON output.

8. **Human-readable output prints one line per item.** Following the existing
   patterns: `Resolved todo: kb-0`, `Archived note: kb-1`, etc. — one line
   per item, in the order the identifiers were given.

9. **Help text and examples updated.** Each affected command's `cmd_man`
   gains examples showing multi-ID usage and multi-ID `--json` usage,
   following the annotation style in `docs/bin/principles.md` (explain *when*
   to use it, not just restate the command).

10. **Root `bs --help` examples updated.** The "Complete and archive" section
    in `main.ml` should show at least one multi-ID command (e.g.
    `bs resolve kb-0 kb-1`) so the capability is discoverable from the
    top-level help.

11. **AGENTS.md template updated for multi-ID lifecycle commands.** The
    `agents_md_template` in `lifecycle.ml` should show multi-ID examples for
    resolve and archive. E.g.:
    ```
    bs resolve kb-0 kb-1
    bs archive kb-5 kb-6
    ```
    *Rationale: agents consume AGENTS.md as their primary command reference.
    If multi-ID isn't shown there, they won't use it.*

12. **AGENTS.md template updated for multi-target relations.** The template
    should add an example showing `relate` with multiple targets in one
    command, e.g.:
    ```
    bs relate kb-2 --depends-on kb-3 --related-to kb-4
    ```
    *Rationale: `relate` already supports this, but the current template only
    shows `bs relate kb-2 --related-to kb-3` with a single target. Agents
    miss the multi-target capability.*

13. **Integration tests for every affected command.** Each command gets
    integration tests covering: multi-ID happy path, multi-ID with `--json`,
    and multi-ID failure (one invalid ID causes atomic rollback with no items
    modified). Existing single-ID JSON tests must be updated to expect the
    new array-wrapped output shape.

14. **Service unit tests for `*_many` functions.** Each new `*_many` service
    function gets unit tests covering: multi-ID success, atomic failure (one
    bad ID fails the batch with no items modified), and single-ID-via-many
    (verifying the function works for the degenerate case). These follow the
    pattern in `delete_service_expect.ml`.
    *Added after codebase analysis: `mutation_service_resolve_expect.ml` and
    `mutation_service_reopen_expect.ml` exist but have no multi-ID tests.
    There is no `mutation_service_archive_expect.ml` at all.*

15. **AGENTS.md uses marker-delimited injection.** The injected section uses
    `※` (U+203B, reference mark) as a boundary marker. The heading becomes
    `## ※ Knowledge Base` and a trailing `※` line marks the end. Uninstall
    finds the heading by matching the marker character, removes everything
    through the trailing marker (or EOF), and no longer relies on exact
    template string matching. This decouples template content changes from
    uninstall correctness.
    *Added after codebase analysis: the current uninstall uses exact string
    matching against the template, so any template change (like adding
    multi-ID examples) would break uninstall on repos initialized with the
    old template.*

16. **`claim` and `update` remain single-ID.** `claim` represents an
    intentional single-item workflow choice. `update` takes per-item flags
    (`--title`, `--content`) that don't generalize to multiple items.

## Scenarios

### Scenario 1: Batch-resolve after finishing work

**Starting state:** kb-0, kb-1, and kb-2 are open todos.

```
$ bs resolve kb-0 kb-1 kb-2
Resolved todo: kb-0
Resolved todo: kb-1
Resolved todo: kb-2
```

All three transition to done. A subsequent `bs list todo --status open` no
longer shows them.

### Scenario 2: Batch-resolve with JSON output

**Starting state:** kb-0 and kb-1 are open todos.

```
$ bs resolve kb-0 kb-1 --json
{"ok":true,"resolved":[{"type":"todo","niceid":"kb-0"},{"type":"todo","niceid":"kb-1"}]}
```

### Scenario 3: Atomic failure — one bad identifier

**Starting state:** kb-0 is an open todo. kb-99 does not exist.

```
$ bs resolve kb-0 kb-99
Error: item not found: kb-99
```

Exit code is non-zero. kb-0 is **not** resolved — the entire batch fails.

### Scenario 4: Batch-archive notes

**Starting state:** kb-5 and kb-6 are active notes.

```
$ bs archive kb-5 kb-6
Archived note: kb-5
Archived note: kb-6
```

### Scenario 5: Batch-reopen mixed item types

**Starting state:** kb-3 is a resolved todo. kb-4 is an archived note.

```
$ bs reopen kb-3 kb-4
Reopened todo: kb-3
Reactivated note: kb-4
```

### Scenario 6: Close as alias

`close` behaves identically to `resolve` in multi-ID mode:

```
$ bs close kb-0 kb-1
Resolved todo: kb-0
Resolved todo: kb-1
```

### Scenario 7: AGENTS.md shows multi-ID and multi-relation

After `bs init`, the AGENTS.md section includes:

```
## ※ Knowledge Base

...

# Complete and archive
bs resolve kb-0 kb-1
bs archive kb-5 kb-6

# Link items after creation
bs relate kb-2 --depends-on kb-3 --related-to kb-4

...

※
```

### Scenario 9: Uninstall removes marker-delimited section

A repo was initialized with an older template. The user upgrades `bs` and
runs `bs uninstall`. Uninstall finds the `## ※ Knowledge Base` heading,
removes everything through the trailing `※`, and cleanly removes the
section regardless of the content between the markers.

### Scenario 8: Single-ID still works, JSON shape unchanged

**Starting state:** kb-0 is an open todo.

```
$ bs resolve kb-0 --json
{"ok":true,"resolved":[{"type":"todo","niceid":"kb-0"}]}
```

Single-ID invocations produce an array of one, keeping the schema uniform.

## Constraints

- **Existing single-ID invocations must not break.** All current CLI forms
  continue to work. The only observable change for single-ID invocations is
  that `--json` output switches from a flat object to an object wrapping a
  one-element array.

- **JSON output shape change is a breaking change for consumers.** The
  current `resolve --json` returns `{"ok":true,"action":"resolved","type":"todo","niceid":"kb-0"}`.
  Switching to `{"ok":true,"resolved":[...]}` changes the schema. This is
  acceptable given the project's pre-1.0 status, but should be called out
  in the commit message.

- **AGENTS.md template changes only affect new `bs init` runs.** Existing
  repositories retain their current AGENTS.md content. This is by design —
  the template is injected once and not auto-updated. However, the
  marker-delimited approach (requirement 15) means uninstall will work
  correctly on repos initialized with either old or new templates, as long
  as the `※` markers are present. Repos initialized before the marker
  change will still use the old heading-based uninstall path.

- **No new runtime dependencies.**

- **`close` must remain a pure alias.** It delegates to `Cmd_resolve.run`
  and must continue to do so — no separate implementation.

- **Return type preservation.** `resolve_many` returns `Todo.t list`,
  `archive_many` returns `Note.t list`, `reopen_many` returns `item list`.
  The type-level guarantee that `resolve` only produces todos (and `archive`
  only notes) must be maintained in the multi-ID variants.

## Open Questions

*All original open questions resolved by codebase analysis. No new open
questions identified.*

## Approaches

The requirements decompose into two independent work areas: (A) multi-ID
service and CLI changes, and (B) AGENTS.md marker-delimited injection. These
can be implemented independently. The approaches below address them separately.

### Multi-ID: Approach 1 — Two-phase validate-then-execute

Follow the `delete_many` pattern exactly. Each `*_many` function in
`Mutation_service` has an explicit validation phase and an execution phase,
connected by `Data.Result.sequence`.

**Mechanism.**

`resolve_many` and `archive_many` map identifiers through `_transition_to`'s
validation logic (find + type check) in Phase 1, collecting validated items.
Phase 2 calls `update` on each. The key change is splitting `_transition_to`
into two steps:

```ocaml
(* Phase 1: validate — find item and check entity type *)
let _validate_transition t ~identifier ~entity_type ~verb =
  let open Item_service in
  let open Result.Syntax in
  let+ item = find t.items ~identifier in
  let actual_type = Data.Item.entity_type item in
  if actual_type <> entity_type then
    Error (Validation_error
      (Printf.sprintf "%s applies only to %ss, but %s is a %s"
         verb entity_type
         (Data.Identifier.to_string (Data.Item.niceid item))
         actual_type))
  else Ok item

(* Phase 2: execute — apply the status change *)
let _execute_transition t item ~target_status =
  let identifier = Data.Item.identifier_string item in
  update t ~identifier ~status:target_status ()
```

`resolve_many`:

```ocaml
let resolve_many t ~identifiers =
  let open Result.Syntax in
  let* validated =
    List.map (fun id ->
      _validate_transition t ~identifier:id ~entity_type:"todo" ~verb:"resolve"
    ) identifiers
    |> Data.Result.sequence
  in
  List.map (fun item ->
    let+ item = _execute_transition t item ~target_status:"done" in
    match item with
    | Item_service.Todo_item todo -> todo
    | _ -> assert false
  ) validated
  |> Data.Result.sequence
```

`archive_many` follows the same shape with `entity_type:"note"` and
`target_status:"archived"`.

`reopen_many` requires a dedicated `_validate_reopen` that checks terminal
state without performing the update:

```ocaml
let _validate_reopen t ~identifier =
  let open Item_service in
  let open Result.Syntax in
  let+ item = find t.items ~identifier in
  match item with
  | Todo_item todo ->
      if Data.Todo.status todo = Data.Todo.Done then Ok item
      else Error (Validation_error (Printf.sprintf "..."))
  | Note_item note ->
      if Data.Note.status note = Data.Note.Archived then Ok item
      else Error (Validation_error (Printf.sprintf "..."))
```

Phase 2 then calls `update` with the appropriate target status per entity
type.

At the `Kb_service` level, each `*_many` is wrapped in `_with_flush` +
`with_transaction`:

```ocaml
let resolve_many t ~identifiers =
  _with_flush t (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () -> Mutation.resolve_many t.mutation ~identifiers))
```

In the bin layer, each command dispatches on identifier count (the delete
pattern):

```ocaml
let run first_identifier rest_identifiers json =
  let identifiers = first_identifier :: rest_identifiers in
  ...
  match identifiers with
  | [id] -> Service.resolve ... ~identifier:id |> Result.map (fun t -> [t])
  | _ -> Service.resolve_many ... ~identifiers
```

**What changes for consumers.** JSON output changes from flat object to
array-wrapped for all invocations (single and multi). Human-readable output
is unchanged for single-ID; multi-ID prints one line per item.

**What changes for tests.** Existing single-ID JSON integration tests must
update their expected output. New integration tests for multi-ID happy path,
JSON, and atomic failure. New service unit tests for each `*_many`. The
existing single-ID service tests are unaffected — the original functions
remain.

**Limitations.** `resolve` and `resolve_many` coexist as separate code paths
through the same data. The single-ID path continues to use the combined
validate+execute `_transition_to`; the multi-ID path uses the split
`_validate_transition` + `_execute_transition`. This is a small duplication
but avoids changing the single-ID path.

### Multi-ID: Approach 2 — Fold-in-transaction

Follow the `show_many` pattern: each `*_many` function is a fold that calls
the existing single-ID function per identifier. Atomicity comes from wrapping
the fold in a SQLite transaction at the `Kb_service` level — if any step
returns `Error`, the transaction rolls back all preceding UPDATEs.

**Mechanism.**

Each `*_many` in `Mutation_service` is a tail-recursive fold, identical in
shape to `show_many`:

```ocaml
let resolve_many t ~identifiers =
  let open Result.Syntax in
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | id :: rest ->
        let* todo = resolve t ~identifier:id in
        go (todo :: acc) rest
  in
  go [] identifiers
```

`archive_many` and `reopen_many` follow the same pattern, calling
`archive` and `reopen` respectively. No changes to the existing single-ID
functions. No `_validate_transition` split. `reopen`'s inline validation
is reused as-is.

At the `Kb_service` level, the transaction provides atomicity:

```ocaml
let resolve_many t ~identifiers =
  _with_flush t (fun () ->
    Repository.Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () -> Mutation.resolve_many t.mutation ~identifiers))
```

`with_transaction` calls `ROLLBACK` when the body returns `Error`, undoing
any UPDATEs from earlier iterations. The observable behavior is identical to
Approach 1: either all items transition or none do.

In the bin layer, two variants are possible:

- **Dispatch** (like delete): single ID calls `Service.resolve`, multi calls
  `Service.resolve_many`. This preserves the non-transactional path for
  single-ID calls.
- **Always-many** (like show): always call `Service.resolve_many`. Simpler
  bin code, but single-ID calls now go through a transaction unnecessarily.

The dispatch variant is recommended — it matches the existing delete pattern
and avoids a transaction for the common single-ID case.

**What changes for consumers.** Same as Approach 1.

**What changes for tests.** Same as Approach 1, with one difference: since the
`*_many` functions call the existing single-ID functions, they inherit their
validation behavior exactly. No risk of Phase 1/Phase 2 divergence.

**Limitations.** Atomicity depends on SQLite transaction rollback rather than
pre-validation. This is a semantic difference from `delete_many`: in
Approach 1, a bad third identifier means no UPDATEs were attempted; in
Approach 2, two UPDATEs were attempted and rolled back. The observable result
is the same (no items changed, same error message), but the mechanism differs.

For mutation commands this is safe — each UPDATE touches one row in one table,
and SQLite rollback is reliable. The concern would be if an UPDATE had
non-transactional side effects (e.g. sending a notification), but the current
service layer has none.

### AGENTS.md: Marker-delimited injection

This is not a choice between approaches — the marker mechanism is
specified by requirement 15. The implementation is described here for
completeness.

**Mechanism.**

The template gains a marker heading and footer:

```ocaml
let agents_md_marker = "※"
let agents_md_section_heading = "## ※ Knowledge Base"

let agents_md_template = {|## ※ Knowledge Base

This repository uses `bs` to track todos and notes. Use it to
externalize work you've identified, decisions, and research.

```
# Create items (content from --content or stdin)
echo "Description" | bs add todo "Title"
echo "Research findings" | bs add note "Title"

# Browse
bs list
bs list --available
bs show kb-0

# Claim and work on todos
bs next --show
bs claim kb-0

# Complete and archive
bs resolve kb-0 kb-1
bs archive kb-5 kb-6

# Link items after creation
bs relate kb-2 --depends-on kb-3 --related-to kb-4
```

Run `bs --help` for the full command reference.

※
|}
```

`install_agents_md` is unchanged — it still checks for the heading and
appends or creates.

`uninstall_agents_md` changes from exact-string matching to marker-based
extraction:

1. Read the file contents.
2. Find the line matching `## ※ Knowledge Base` (the heading).
3. Find the next line that is exactly `※` (the footer) after the heading.
4. If both found: remove from heading through footer (inclusive), trim
   trailing whitespace. If the result is empty, delete the file
   (`File_deleted`); otherwise write back (`Section_removed`).
5. If heading found but no footer: `Section_modified` (manual intervention).
6. If heading not found: fall back to legacy exact-string matching for
   pre-marker repos, then `Not_found`.

Step 6 provides backward compatibility with repos initialized before the
marker change. Once pre-marker repos age out, the fallback can be removed.

**What changes for tests.** The existing `init_expect.ml` and
`uninstall_expect.ml` integration tests must update expected AGENTS.md
content. New tests: uninstall after template content change (the scenario
that currently yields `Section_modified` should now yield
`Section_removed`), and uninstall on a pre-marker repo (backward compat).

## Design Decisions

1. **Action-specific JSON array keys** (`"resolved"`, `"archived"`,
   `"reopened"`). Considered a generic `"items"` key shared across all
   commands. Chose action-specific keys for consistency with the existing
   `delete` command (`"deleted"`) and `show` command (`"items"` — which
   is the appropriate action-specific key for a query). Each command's JSON
   shape is self-describing.

2. **Single-ID JSON output changes to array-wrapped.** Considered keeping
   the flat object for single-ID and only using arrays for multi-ID.
   Chose uniform array-wrapped output because consumers should not need to
   branch on whether the result is an object or an array — a single
   schema per command is simpler to program against. The breaking change
   is acceptable pre-1.0.

3. **Separate `*_many` functions alongside existing single-ID functions.**
   Considered replacing the single-ID functions with list-accepting
   versions. Chose separate functions because: (a) the return types differ
   (`Todo.t` vs `Todo.t list`) and callers of the single-ID path would
   need unnecessary unwrapping; (b) the single-ID path avoids transaction
   overhead; (c) it matches the established `delete` / `delete_many`
   convention.

4. **`※` marker for AGENTS.md injection boundaries.** Considered HTML
   comments (`<!-- bs:begin -->`), invisible Unicode characters, and a
   footer-only approach. HTML comments are not valid markdown per the
   requirement. Invisible characters are impossible to debug. Footer-only
   with "next heading" heuristic is fragile if the user adds content after
   the section. The reference mark is a visible, valid markdown character
   that is distinctive enough to match on and looks intentional as
   decoration.

## Consequences and Trade-offs

**Code duplication.** Approach 1 (two-phase) introduces parallel
validate/execute helpers alongside the existing combined `_transition_to`.
The duplication is small (the validate step is the find + type check, which
is ~5 lines per operation) but it means changes to validation logic must be
kept in sync. Approach 2 (fold) has zero duplication — the `*_many`
functions are 6-line folds that delegate entirely to the existing single-ID
functions.

**Atomicity mechanism.** Approach 1 achieves atomicity by not attempting
UPDATEs until validation passes. Approach 2 achieves atomicity via
transaction rollback. Both produce identical observable behavior. Approach 1
is "correct by construction" — a bug in Phase 2 cannot leave partial state
because Phase 1 already verified everything. Approach 2 is "correct by
rollback" — a bug in the single-ID function that somehow partially commits
would be caught by the transaction boundary. In practice, SQLite transactions
are reliable and the single-ID functions are well-tested, so the distinction
is academic.

**Consistency with existing patterns.** Approach 1 matches `delete_many`
exactly. Approach 2 matches `show_many` exactly. Both are established
patterns in the codebase. The question is which precedent is more relevant:
`delete_many` (also a mutation, also needs atomicity) or `show_many` (also a
multi-ID variant of a single-ID function, zero duplication).

**Complexity.** Approach 1 requires splitting `_transition_to` into
validate + execute, writing a dedicated `_validate_reopen`, and maintaining
both paths. Approach 2 requires only the 6-line fold functions. The
complexity difference is modest but favors Approach 2, especially for
`reopen` where the inline validation is the most involved.

**Migration path.** Both approaches are additive — they add new functions
without changing existing ones. Starting with Approach 2 does not preclude
moving to Approach 1 later if a need for pre-validation (e.g. dry-run
support) arises.

## Requirement Coverage

Coverage analysis for the recommended approach (Approach 2):

| # | Requirement | Satisfied by |
|---|-------------|--------------|
| 1 | `resolve` multi-ID | `resolve_many` fold + bin dispatch |
| 2 | `close` multi-ID | `cmd_close.ml` wires same args to `Cmd_resolve.run` |
| 3 | `archive` multi-ID | `archive_many` fold + bin dispatch |
| 4 | `reopen` multi-ID | `reopen_many` fold + bin dispatch |
| 5 | Atomic error semantics | `with_transaction` at `Kb_service` level; rollback on error |
| 6 | Service `*_many` in `Mutation_service` | Three fold functions, wrapped by `_with_flush` + `with_transaction` in `Kb_service` |
| 7 | Action-specific JSON array keys | Per-command `result_to_json` + array key in `cmd_*.ml` |
| 8 | One line per item, input order | `List.iter` in bin layer |
| 9 | Help text updated | `cmd_man` additions in each `cmd_*.ml` |
| 10 | Root help updated | `main.ml` examples section |
| 11 | AGENTS.md multi-ID examples | Updated `agents_md_template` |
| 12 | AGENTS.md multi-relation example | Updated `agents_md_template` |
| 13 | Integration tests | New multi-ID tests + updated single-ID JSON expectations |
| 14 | Service unit tests | New `*_many` tests in `mutation_service_*_expect.ml` |
| 15 | Marker-delimited AGENTS.md | `※` heading + footer, marker-based uninstall |
| 16 | `claim`/`update` single-ID | No changes to those commands |

## Recommendation

**Approach 2 (fold-in-transaction)** for multi-ID service changes.

It is simpler: three 6-line fold functions vs. split validate/execute
helpers. It reuses existing single-ID functions with zero duplication,
which means `reopen`'s inline validation works without extraction. It
matches the `show_many` precedent. Atomicity is provided by
`with_transaction`, which is the same mechanism `delete_many` uses at the
`Kb_service` level — the difference is only that `delete_many` also
pre-validates (because its cascade deletes are harder to reason about than
single-row UPDATEs).

The fallback is Approach 1 if a future requirement (e.g. dry-run mode,
detailed per-item error reporting) needs pre-validation as a separate
phase. The fold structure of Approach 2 can be replaced with two-phase
functions without changing the bin layer or JSON output — the refactor
is internal to `Mutation_service`.
