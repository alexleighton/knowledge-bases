# Design: Feature gaps for agent-oriented knowledge bases

## Problem Statement

`bs` provides the core operations for a repository-local knowledge base:
create todos and notes, list and show them, move them through a lifecycle,
and link them with typed relations. This is sufficient for basic tracking, but
several gaps limit its usefulness as a primary working tool for coding agents.

**Lifecycle is one-way and incomplete.** Items can be created and moved to
terminal states (done, archived), but never deleted or reversed. A todo
resolved prematurely cannot be reopened without creating a duplicate. An item
created by mistake persists forever. Relations, once created, cannot be
removed. For agents that create items speculatively and iterate on structure,
this rigidity forces workarounds.

**Items have no temporal dimension.** There are no timestamps — no
`created_at`, no `updated_at`. Without them, there's no way to detect stale
in-progress todos, sort by recency, or implement age-based cleanup. This is
infrastructure: timestamps aren't directly valuable, but multiple useful
features depend on them.

**The knowledge base accumulates clutter.** Resolved todos and archived
notes remain in the store indefinitely. For short-lived tracking items —
a todo that spans a few commits, a note capturing a decision that gets folded
into code — terminal items quickly outnumber active ones. There is no cleanup
mechanism, manual or automatic.

**The relation graph is underexposed.** The relation model supports
dependencies, bidirectional links, custom kinds, and blocking semantics, but
the query surface is limited to immediate neighbors via `show`. An agent
cannot ask "what transitively depends on this item?" or filter `list` by
relation. The graph data exists; the access paths don't.

## Background

### Codebase structure

The codebase has four layers with downward-only dependencies:

```
Service    → business operations          (11 modules, 1922 lines)
Repository → persistence (SQLite, JSONL)  ( 8 modules, 1390 lines)
Control    → control flow, I/O            ( 3 modules,  116 lines)
Data       → domain types, value objects   (16 modules,  961 lines)
```

The CLI (`bin/`, 17 files, 1113 lines) is thin wiring on top of Service.
Unit tests (`test/`, 35 files, 4143 lines) cover every layer. Integration
tests (`test-integration/`, 17 files, 3389 lines) exercise every command as
a subprocess.

### Data types — no timestamp fields

`Data.Todo.t` and `Data.Note.t` are abstract record types with five fields
each:

```ocaml
(* lib/data/todo.ml *)
type t = { id : id; niceid : Identifier.t; title : Title.t;
           content : Content.t; status : status }
```

```ocaml
(* lib/data/note.ml *)
type t = { id : id; niceid : Identifier.t; title : Title.t;
           content : Content.t; status : status }
```

Both types follow the Correct Construction pattern: abstract `type t`,
smart constructor `make` that validates the TypeId prefix, accessors, and
`with_*` updaters that return new records. Neither type has a `created_at`
or `updated_at` field today. Adding timestamps requires changes to:

- `make` (two new parameters)
- The `with_*` updaters (to refresh `updated_at`)
- `pp`/`show` (to include timestamps in the derived representation)

The types are isomorphic — same five fields, same `make` signature, same
accessor set. A timestamp addition doubles down on this parallelism.

### SQLite schema — no timestamp columns

The `todo` and `note` tables mirror their data types exactly:

```sql
-- lib/repository/todo.ml:44–50
CREATE TABLE IF NOT EXISTS todo (
  id TEXT PRIMARY KEY,
  niceid TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  status TEXT NOT NULL
);
```

The `note` table is identical except for the table name. Neither table has
`created_at` or `updated_at` columns. Adding columns requires `ALTER TABLE`
or a full rebuild. Since `force_rebuild` already drops and recreates all
tables (via `delete_all` then `import`), timestamp columns can be added to
the `CREATE TABLE` statements and populated during the next rebuild.

The `_todo_of_row` and `_note_of_row` functions (`todo.ml:31–40`,
`note.ml:31–40`) parse result rows by column index. Adding columns means
adjusting these indices in every SELECT statement (6 in `todo.ml`, 6 in
`note.ml`).

### JSONL format — no timestamp fields

The JSONL serialization (`lib/repository/jsonl.ml`) writes five fields per
todo and note:

```ocaml
(* jsonl.ml:19–26 *)
let _todo_to_json todo =
  `Assoc [
    ("type", `String "todo");
    ("id", `String ...);
    ("title", `String ...);
    ("content", `String ...);
    ("status", `String ...);
  ]
```

The parser (`_parse_todo_record`, `_parse_note_record`) reads these five
fields back. Adding `created_at` and `updated_at` requires extending both
the serializer and the parser. The `_get_string` helper can be used; for
backward compatibility during the transition, `_get_string` could use
an optional default, though since we are pre-release, strict parsing is
acceptable.

The `entity_record` type that bridges JSONL and rebuild also has no
timestamp fields:

```ocaml
type entity_record =
  | Todo of { id; title; content; status }
  | Note of { id; title; content; status }
  | Relation of Data.Relation.t
```

This type appears in both `jsonl.mli` (public API) and is consumed by
`sync_service.ml:109–123` during `force_rebuild`.

### Repository delete operations — present but incomplete

Both `Repository.Todo` and `Repository.Note` expose a `delete` function
that removes an item by niceid:

```ocaml
val delete : t -> Data.Identifier.t -> (unit, error) result
```

Both use `DELETE FROM <table> WHERE niceid = ?` and check `Sql.changes` to
detect not-found. However, these are bare deletes — they do not touch the
`niceid` table or the `relation` table. Today, `delete` is only used
internally by `delete_all` (bulk table truncation during rebuild), not
exposed through any service or CLI command.

The `niceid` table (`lib/repository/niceid.ml`) maps `typeid → (namespace,
niceid)`. Deleting an item from the `todo` or `note` table leaves an orphan
entry in `niceid`. This is harmless during normal operation (the niceid is
simply not resolvable), but is a data inconsistency. Currently, niceid
cleanup only happens via `delete_all` during a full rebuild.

### Relation repository — no per-entity delete

`Repository.Relation` exposes:

```ocaml
val create     : t -> Data.Relation.t -> (Data.Relation.t, error) result
val list_all   : t -> (Data.Relation.t list, error) result
val find_by_source : t -> Typeid.t -> (Data.Relation.t list, error) result
val find_by_target : t -> Typeid.t -> (Data.Relation.t list, error) result
val delete_all : t -> (unit, error) result
```

There is no `delete` for a single relation, no `delete_by_source`, and no
`delete_by_target`. The table has a composite primary key
`(source, target, kind)`, which means a single-relation delete needs all
three values. A per-entity cascade delete (for the delete command) would
need `DELETE FROM relation WHERE source = ? OR target = ?`.

For bidirectional relations, the `create` function checks for the reverse
direction before inserting (`_reverse_exists`, line 35–53). An `unrelate`
command would need the same reverse-aware logic: if the user says
`unrelate kb-3 --related-to kb-1`, and the stored relation is actually
`(kb-1, kb-3, related-to)`, the delete must find and remove that row.

### Service mutation paths — no reopen

The mutation service (`lib/service/mutation_service.ml`, 142 lines)
provides:

- `update` — generic field update with no-op detection
- `resolve` — sets todo status to Done (validates item is a todo, delegates
  to `update`)
- `archive` — sets note status to Archived (validates item is a note,
  delegates to `update`)
- `claim` — sets open, unblocked todo to In_Progress
- `next` — finds first open, unblocked todo and claims it

`resolve` calls `update` with `~status:"done"` after validating the item is
a todo (`mutation_service.ml:70–83`). `archive` calls `update` with
`~status:"archived"` after validating the item is a note
(`mutation_service.ml:128–141`). Both are one-way: there is no
corresponding `reopen` or `reactivate`.

`update` detects no-op changes via `_todo_changed` / `_note_changed`
(lines 25–33), which compare status, title, and content. Adding timestamps
means `updated_at` changes on every mutation, so the no-op detection
would need to exclude `updated_at` from the comparison (or `updated_at`
would be set only when other fields change).

### The _with_flush pattern

Every write operation in `Kb_service` goes through `_with_flush`:

```ocaml
let _with_flush t f =
  mark_dirty → f () → flush
```

This marks the database dirty before the write and flushes to JSONL after.
`_with_flush_map` is a variant that accepts a custom error mapper (used by
`next` and `claim` which have `claim_error` instead of `error`).

GC-on-every-command (requirement 19) would need to hook into this same
pipeline or into `open_kb`. Running GC before the main operation is
cleaner (the listing a user sees is already cleaned), but it means every
read command (list, show) also triggers GC. `open_kb` already calls
`rebuild_if_needed` at startup, so there is an existing precedent for
work-on-open.

### Query service — list and show

`Query_service.list` (`query_service.ml:71–124`) accepts `entity_type`,
`statuses`, and `available`. The function dispatches to `Repository.Todo.list`
and `Repository.Note.list`, then merges and sorts results by niceid `raw_id`.

Adding relation-based filtering (requirement 13) would insert a new code
path. The current flow is: fetch items → merge → sort. With relation
filters, it would become: resolve filter target → find relations → intersect
with item results → merge → sort. The relation data comes from
`Repository.Relation.find_by_target` (to find items that relate *to* a
given item).

For transitive queries (requirement 14), the current relation repository
provides only direct lookups (`find_by_source`, `find_by_target`).
Transitive traversal would require either:

1. Application-level BFS/DFS: call `find_by_target` repeatedly, collecting
   reachable items. This is the pattern already used in
   `Relation_service.find_blockers` (line 64–82), which traverses
   blocking relations one hop at a time.
2. A recursive CTE in SQLite: `WITH RECURSIVE` can traverse the relation
   table in a single query. SQLite supports this natively.

The existing codebase uses application-level traversal exclusively —
`find_blockers` iterates over `find_by_source` results and resolves each
target via `Item_service.find`. There are no recursive CTEs anywhere in the
codebase.

`Query_service.show` (`query_service.ml:163–192`) resolves an item, fetches
its outgoing relations (`find_by_source`), its incoming relations
(`find_by_target`), and builds `relation_entry` records for display. For
bidirectional relations stored as incoming, they are folded into the
outgoing list. The `show` output does not include timestamps today because
the data type has none.

### Sort order

All listing queries sort by niceid `raw_id` (creation order):

```ocaml
(* query_service.ml:50–51 *)
let sort_items items =
  List.sort (fun a b -> Int.compare (raw_id_of_item a) (raw_id_of_item b)) items
```

Repository-level listing also sorts by niceid (`ORDER BY niceid`). Adding
`--sort created` or `--sort updated` requires either:

- Sorting in-memory after fetch (items have timestamps), or
- Passing a sort column to the repository and adding `ORDER BY created_at`
  / `ORDER BY updated_at` to the SQL.

The current pattern is dual-sort: SQL sorts within each type, then
`sort_items` sorts the merged result. A timestamp sort would need to
replicate this dual approach.

### CLI output patterns

**Show output** (`bin/cmd_show.ml`) formats items as:

```
todo kb-0 (todo_01abc...)
Status: open
Title:  Fix timeout handling

Content here...
```

Adding timestamps would insert two lines after Status. The JSON output
(`item_to_json`, lines 68–92) builds an `Assoc` list with the item's
fields; adding `created_at` and `updated_at` keys is straightforward.

**List output** (`bin/cmd_list.ml`) uses a columnar format:

```
kb-0     todo  open         Fix CI
```

The list output does not include timestamps in text mode (the columns are
already dense). Timestamps might only appear in JSON list output or be
omitted from list entirely (they're visible via show).

**Command structure.** New commands (delete, unrelate, reopen, gc) follow
the existing pattern:

1. A `run` function that calls `App_context.init`, invokes a `Kb_service`
   method, formats output (text or JSON), and uses
   `Common.exit_with_error` for failures.
2. Cmdliner `Arg` and `Term` definitions.
3. A `Cmd.v` registered in `main.ml:57–62`.

Each command is a single file averaging 40–70 lines. `cmd_resolve.ml` (40
lines) is the minimal template. `cmd_show.ml` (136 lines) is the largest,
containing output helpers reused by `cmd_claim.ml` and `cmd_next.ml`.

The shared relation flags (`--depends-on`, `--related-to`, `--uni`, `--bi`,
`--blocking`) are defined once in `cmdline_common.ml:43–74` and shared by
`cmd_add.ml` and `cmd_relate.ml`. An `unrelate` command would reuse these
same flags.

### Config repository

`Repository.Config` is a simple key-value store (`config` table with
`key TEXT PRIMARY KEY, value TEXT NOT NULL`). It currently stores three
keys: `namespace`, `dirty`, and `content_hash`. GC max-age configuration
(requirement 17) would add a fourth key (e.g., `gc_max_age`). The
`Config` API (`get`, `set`, `delete`) is sufficient — no new repository
operations needed.

### Sync and rebuild

`Sync_service.force_rebuild` (`sync_service.ml:89–126`) reads the JSONL
file, truncates all tables (`delete_all` on todo, note, relation, niceid),
then re-imports every record. The import path uses `Repository.Todo.import`
and `Repository.Note.import`, which allocate fresh niceids via
`Niceid.allocate`.

For timestamps: `import` would need to accept `created_at` and `updated_at`
parameters from the JSONL record. Currently `import` takes `~id ~title
~content ?status ()` — two new labeled parameters are needed.

For GC: if automatic GC runs on open, it interacts with the
rebuild-on-open path (`rebuild_if_needed`). The sequence would be:
open → rebuild if needed → GC if configured → main operation. Both
rebuild and GC modify data and trigger a flush; care is needed to avoid
double-flushing or marking dirty after a just-completed flush.

### Test coverage for affected areas

**Data layer tests.** `test/data/todo_expect.ml` and
`test/data/note_expect.ml` test construction, status conversion, accessors,
and `with_*` updaters. Adding timestamp fields to `make` changes every
test call site.

**Repository tests.** `test/repository/todo_repo_expect.ml` and
`test/repository/note_repo_expect.ml` test CRUD operations, listing with
status filters, and error cases. `test/repository/relation_repo_expect.ml`
tests create, duplicate detection, bidirectional reverse checking, and
find_by_source/target. `test/repository/jsonl_expect.ml` tests
serialization round-trips. All repository tests use an in-memory SQLite
database via `test/repository/test_helpers.ml`.

**Service tests.** `test/service/mutation_service_expect.ml` tests update,
resolve, archive, claim, next, and no-op detection.
`test/service/query_service_expect.ml` tests list filtering, available
filtering, and show with relations.
`test/service/relation_service_expect.ml` tests relate_many, find_blockers,
and build_specs. `test/service/sync_service_expect.ml` tests flush, rebuild,
and rebuild_if_needed. All service tests create temporary git repositories.

**Integration tests.** Every command has a corresponding `*_expect.ml`
file. `workflow_expect.ml` exercises a multi-command lifecycle. New commands
need new test files; changed commands (list, show) need updated snapshots.

### Observations

1. **Repository.Todo.delete and Repository.Note.delete exist but are
   orphaned.** They delete from the entity table only — no niceid cleanup,
   no relation cascade. They are not called from any service or CLI command.
   A delete feature would either extend these to handle cascade, or add a
   new service-layer delete that orchestrates the cleanup.

2. **The relation repository has no single-relation delete.** Adding
   `unrelate` requires a new `Repository.Relation.delete` function that
   takes `(source, target, kind)` and handles the bidirectional reverse
   lookup. The existing `_reverse_exists` helper in `relation.ml:35–53`
   does the directional lookup needed, but for deletion rather than
   existence checking.

3. **The niceid allocator has no per-entry delete.** Deleting an item
   leaves its niceid entry orphaned. This means deleted niceids are never
   reused — the allocator always takes `MAX(niceid) + 1`. This is
   consistent with the append-only nature of the existing design, but GC
   over time would accumulate gaps. Whether this matters depends on scale.

4. **No-op detection in mutation_service will interact with timestamps.**
   `_todo_changed` and `_note_changed` compare status, title, and content.
   If `updated_at` is set on every `with_*` call, the no-op check would
   need to compare only the user-visible fields, not the timestamp. If
   `updated_at` is set only when the no-op check passes, the timestamp
   is purely a service concern, not a data concern.

5. **`sort_items` in query_service is hardcoded to niceid order.** Adding
   `--sort` requires parameterizing this function. The comparator would
   need access to timestamps, which means the item types must carry them.

6. **The `_with_flush` pattern wraps every write but no reads.** GC on
   every command (requirement 19) would need to trigger on reads too.
   `open_kb` already does work (rebuild_if_needed) and would be the
   natural hook, but it returns the service handle before any GC runs.
   An alternative: `open_kb` runs GC before returning, so all subsequent
   operations see a clean state.

7. **`force_rebuild` drops and recreates everything.** This is a clean
   migration path for schema changes: add new columns to `CREATE TABLE`,
   add new fields to `import`, and the next rebuild populates them.
   Pre-release, this is the simplest way to introduce timestamps.

8. **Bidirectional relation storage is asymmetric.** A bidirectional
   relation is stored as a single row with one direction (source →
   target). `show` handles this by folding bidirectional-incoming into
   outgoing. `unrelate` must replicate this: when the user says
   `unrelate kb-3 --related-to kb-1`, the stored row might be
   `(kb-1, kb-3, related-to)`, and the delete must find it.

9. **`Cmd_show` exports helpers used by other commands.** `item_to_json`,
   `format_show_result`, and `relation_entry_to_json` are consumed by
   `Cmd_claim` and `Cmd_next`. New commands that display item details
   (e.g., `delete --show` or `reopen --show`) would also need these.
   If more commands use them, extracting to a shared output module may
   be warranted.

10. **The config table stores GC-relevant data.** `dirty` and
    `content_hash` are already in config. Adding `gc_max_age` fits the
    existing pattern. The config repository's `get`/`set`/`delete` API
    is sufficient — no new operations needed.

## Requirements

### 1. Timestamps

1. **All items must record `created_at` and `updated_at` timestamps.**
   Both are set on creation; `updated_at` is refreshed on any mutation
   (status change, title edit, content edit). Timestamps are UTC, integer
   seconds since the Unix epoch. *Rationale: prerequisite for age-based
   cleanup, staleness detection, and recency-based ordering. Integer seconds
   avoid floating-point ambiguity and are sufficient for the use case.*

2. **`updated_at` is set at the service layer, after no-op detection.**
   The data layer's `with_*` updaters do not touch timestamps. The service
   layer sets `updated_at` only when a mutation actually changes user-visible
   fields (status, title, content). *Rationale: codebase analysis showed
   `_todo_changed` / `_note_changed` compare status, title, and content. If
   `updated_at` were set in the data layer on every `with_*` call, no-op
   detection would need to exclude it. Keeping timestamps as a service
   concern is simpler and preserves the existing no-op logic.* (Refined
   after background observation 4.)

3. **Timestamps must appear in `show` output** in both human-readable and
   JSON formats. In text mode, they appear as `Created:` and `Updated:`
   lines after `Status:`. In JSON, they appear as `created_at` and
   `updated_at` fields (ISO 8601 strings). *Rationale: agents and humans
   need to see when something was created or last modified.*

4. **Timestamps appear in `list` JSON output but not in text output.** The
   text columnar format remains compact (`niceid  type  status  title`).
   JSON list output includes `created_at` and `updated_at` per item.
   *Rationale: the text format is already dense. Agents use `--json`; humans
   use `show` for details.*

5. **`list` supports `--sort created` and `--sort updated`.** Both sort
   descending (newest first) by default. An `--asc` flag reverses to
   ascending. Without `--sort`, the default remains niceid order. *Rationale:
   "what was added recently" and "what hasn't been touched in a while" are
   the primary agent queries. Descending is the more useful default for
   recency queries.*

6. **Timestamps must survive the JSONL round-trip.** They are stored in the
   JSONL format as ISO 8601 strings so that `flush` → `rebuild` preserves
   them. The `entity_record` type, `import` functions, and JSONL
   serializer/parser all gain timestamp fields. *Rationale: timestamps in
   SQLite only would be lost on rebuild.* (Refined after background analysis
   of the JSONL format and sync_service rebuild path.)

### 2. Delete

7. **A new `bs delete` command removes an item from the knowledge base
   entirely.** The item no longer appears in `list`, `show`, or the JSONL
   file. *Rationale: items created by mistake, or terminal items that have
   outlived their usefulness.*

8. **Deleting an item cascade-deletes all relations involving it** (both as
   source and target), **and removes the item's niceid mapping.** *Rationale:
   dangling relations and orphaned niceid entries are invalid state. Codebase
   analysis showed the existing `Repository.Todo.delete` and
   `Repository.Note.delete` only delete from the entity table — they do not
   touch the `niceid` or `relation` tables. The delete feature must
   orchestrate cleanup across all three.* (Refined after background
   observations 1 and 3.)

9. **Deleting an item that is the target of a blocking relation on a
   non-terminal item requires `--force`.** Without `--force`, the command
   refuses and reports which items would lose a dependency. With `--force`,
   the item and all its relations are deleted. *Rationale: deleting a
   dependency that an open todo relies on changes that todo's blocking state.
   The caller should acknowledge this explicitly.*

10. **`bs delete` accepts multiple identifiers** in a single invocation.
    *Rationale: batch cleanup is the common case.*

### 3. Unrelate

11. **A new `bs unrelate` command removes a specific relation.** It takes a
    source, a kind flag, and a target, mirroring `bs relate` syntax. For
    example: `bs unrelate kb-3 --depends-on kb-5`. The existing shared
    relation flags (`--depends-on`, `--related-to`, `--uni`, `--bi`) in
    `cmdline_common.ml` are reused. *Rationale: relations created by
    mistake, or dependencies that are no longer relevant.* (Refined after
    background analysis of the shared flag definitions.)

12. **For bidirectional relations, `unrelate` works from either endpoint.**
    If `kb-3 related-to kb-1` exists, both `bs unrelate kb-3 --related-to
    kb-1` and `bs unrelate kb-1 --related-to kb-3` remove it. The
    implementation must handle the asymmetric storage of bidirectional
    relations (stored as a single row in one direction). *Rationale:
    bidirectional relations have no canonical direction from the user's
    perspective.* (Refined after background observation 8 — bidirectional
    storage asymmetry.)

### 4. Reopen and reactivate

13. **A new `bs reopen` command transitions a done todo back to open.**
    The item must be in a terminal state (done for todos, archived for
    notes); reopening a non-terminal item is an error. *Rationale: agents
    make mistakes. A prematurely resolved todo should be recoverable without
    creating a duplicate.*

14. **`bs reopen` also works on archived notes, transitioning them back to
    active.** A single command handles both entity types by inspecting the
    item type. *Rationale: one command is simpler for agents than separate
    `reopen` and `reactivate` commands. This follows the pattern of
    `resolve` (todo-specific) and `archive` (note-specific) but unifies
    the reverse direction since the semantics are the same.*

### 5. Relation-based list filtering

15. **`list` supports filtering by relation to a specific item** using the
    built-in relation flags (`--depends-on`, `--related-to`) and custom
    relation kind flags (`--uni`, `--bi`). For example,
    `bs list --depends-on kb-5` shows all items that depend on kb-5.
    `bs list --uni blocks,kb-3` shows all items with a unidirectional
    `blocks` relation to kb-3. *Rationale: "what depends on this item" is
    the primary graph query for agents working through dependency trees.
    Custom kind filtering is needed because user-defined relation kinds are
    a first-class feature.* (Expanded after refinement discussion — initial
    requirements only covered built-in kinds.)

16. **`list` supports a `--transitive` modifier** that expands relation
    filters to include indirect matches. For example,
    `bs list --depends-on kb-5 --transitive` returns direct and transitive
    dependents. The traversal uses application-level BFS, consistent with
    the existing `find_blockers` pattern in `Relation_service`. *Rationale:
    when resolving a foundational item, an agent needs the full impact.*
    (Implementation approach resolved by background analysis — the codebase
    uses application-level traversal exclusively, no recursive CTEs.)

17. **Relation filters compose with existing type and status filters.** For
    example, `bs list todo --status open --depends-on kb-5` shows only open
    todos that depend on kb-5. *Rationale: the common query is "what open
    work is affected by this item."*

18. **`--transitive` requires exactly one relation filter.** Combining
    `--transitive` with multiple relation flags (e.g.,
    `--depends-on kb-5 --related-to kb-3 --transitive`) is an error.
    *Rationale: transitive traversal across mixed relation kinds has
    ambiguous semantics. The constraint keeps the feature predictable.*
    (New requirement surfaced during cross-cutting analysis of flag
    interactions.)

19. **`list` flag interaction rules.** The following flag combinations are
    errors:
    - `--available` + `--status` (existing — mutually exclusive filters)
    - `--sort` + `--count` (sorting counts is meaningless)
    - `--transitive` without a relation filter (nothing to traverse)
    - `--transitive` with multiple relation filters (ambiguous semantics)

    The following compose naturally:
    - `--sort` + `--available` (sort the available todos by timestamp)
    - `--count` + `--available` (count available todos)
    - `--sort` + relation filters (sort the filtered results)
    - `--count` + relation filters (count the filtered results)

    *Rationale: explicit blocking prevents confusing behavior. The existing
    pattern (`--available` blocks `--status`) is extended consistently.*
    (New requirement — resolved from open question 2 and cross-cutting
    analysis of accumulating `list` flags.)

### 6. Garbage collection

20. **A `bs gc` command removes terminal-state items older than a configured
    maximum age.** "Terminal" means `done` for todos, `archived` for notes.
    Age is measured from `updated_at` — the time the item entered its
    terminal state. *Rationale: short-lived tracking items accumulate and
    clutter the knowledge base.*

21. **The maximum age is a persistent configuration value**, stored in the
    knowledge base config table (e.g., via `bs gc --set-max-age 14d`). A
    sensible default (e.g., 30 days) applies when no value is configured.
    The config key is `gc_max_age`. *Rationale: different projects have
    different retention needs.* (Refined to name the config key, since
    background analysis confirmed the config table pattern.)

22. **GC uses transitive anchoring.** A terminal item is retained if any
    item reachable from it through the relation graph (in either direction)
    is non-terminal. Only when an entire connected component of
    age-eligible terminal items has no reachable non-terminal item is the
    component removed. *Rationale: a chain of related terminal items may
    represent context needed to complete a remaining non-terminal item.
    Deleting intermediate items severs that context. The graph traversal
    needed here is shared with `--transitive` on `list`.* (Resolved from
    open question 1 — user chose transitive anchoring.)

23. **GC runs automatically during `open_kb`** when a max-age policy is
    configured. Eligible items are cleaned up after `rebuild_if_needed`
    and before the service handle is returned, so all subsequent operations
    see a clean state. `bs gc` also exists for explicit invocation.
    *Rationale: agents won't remember to run `gc`. The `open_kb` function
    already performs work on open (rebuild_if_needed), establishing a
    precedent.* (Refined after background analysis of the `_with_flush`
    pattern — hooking into `open_kb` is cleaner than wrapping every read.)

24. **GC performance must be benchmarked.** After implementation, a
    performance test in `test-perf/` must measure GC scan time with at
    least 500 items and 1000 relations, targeting < 50ms. If the benchmark
    exceeds this threshold, a "last GC time" optimization should be added:
    store the timestamp of the last GC run in the config table
    (`gc_last_run`) and skip the scan if less than a configurable interval
    has elapsed (e.g., 1 hour). The benchmark is the trigger — do not add
    the optimization speculatively. *Rationale: transitive anchoring
    requires graph traversal on every `open_kb`. For the expected scale
    (dozens of items) this is negligible, but the design should establish
    a concrete performance gate.* (Resolved from open question 1.)

25. **`bs gc` supports `--dry-run`**, reporting what would be removed without
    removing it. *Rationale: visibility into the cleanup policy before it
    acts, useful when tuning the max-age setting.*

### 7. Statistics

26. **`bs list --count` outputs item counts instead of item listings.**
    Counts are broken down by type and status (e.g., "3 open todos, 1
    in-progress, 4 active notes"). Composes with filters:
    `bs list todo --count` shows only todo counts. *Rationale: quick health
    check for agents deciding whether to create more items or focus on
    existing ones.*

### 8. Cross-cutting: repository operations for delete and unrelate

27. **`Repository.Relation` must gain `delete` and `delete_by_entity`
    operations.** `delete` removes a single relation by `(source, target,
    kind)`. `delete_by_entity` removes all relations where a given TypeId
    appears as source or target. Both are needed: `delete` for `unrelate`,
    `delete_by_entity` for cascade delete and GC. *Rationale: the relation
    repository currently has no delete operations other than `delete_all`.
    Codebase analysis confirmed this is the primary gap.* (New requirement
    from background observation 2.)

28. **`Repository.Niceid` must gain a per-entry `delete` operation** that
    removes the niceid mapping for a given TypeId. Used by the delete
    cascade to clean up orphaned entries. *Rationale: codebase analysis
    showed the niceid allocator only has `allocate` and `delete_all`.
    Deleting an item without cleaning up its niceid leaves orphaned data.*
    (New requirement from background observation 3.)

## Scenarios

### Timestamps in show output

Starting state: kb-0 is an open todo created on 2026-03-15.

```
$ bs show kb-0
todo kb-0 (todo_01abc...)
Status:  open
Created: 2026-03-15 14:30:00 UTC
Updated: 2026-03-15 14:30:00 UTC
Title:   Fix timeout handling

The retry logic swallows timeout errors silently.
```

After updating the title:

```
$ bs update kb-0 --title "Fix silent timeout swallowing"
Updated todo: kb-0

$ bs show kb-0
todo kb-0 (todo_01abc...)
Status:  open
Created: 2026-03-15 14:30:00 UTC
Updated: 2026-03-16 09:15:00 UTC
Title:   Fix silent timeout swallowing
...
```

### Timestamps in list JSON output

```
$ bs list --json
{"ok":true,"items":[
  {"niceid":"kb-0","type":"todo","status":"open",
   "title":"Fix timeout handling",
   "created_at":"2026-03-15T14:30:00Z",
   "updated_at":"2026-03-15T14:30:00Z"},
  ...
]}
```

Text output remains unchanged — no timestamps in columnar format.

### Sort by recency

```
$ bs list --sort updated
kb-0  todo  open    Fix silent timeout swallowing
kb-3  todo  open    Refactor DB module
kb-1  note  active  Connection pooling results

$ bs list --sort created --asc
kb-1  note  active  Connection pooling results
kb-3  todo  open    Refactor DB module
kb-0  todo  open    Fix silent timeout swallowing
```

### Delete with blocking guard

Starting state: kb-3 (open todo) depends-on kb-5 (open todo).

```
$ bs delete kb-5
Error: kb-5 is a blocking dependency of: kb-3 (open)
Use --force to delete anyway.

$ bs delete kb-5 --force
Deleted todo: kb-5
  Removed relation: kb-3 depends-on kb-5
```

### Batch delete

```
$ bs delete kb-7 kb-8 kb-9
Deleted note: kb-7
Deleted todo: kb-8
Deleted note: kb-9
```

### Unrelate from either endpoint

Starting state: kb-2 related-to kb-4 (bidirectional).

```
$ bs unrelate kb-4 --related-to kb-2
Unrelated: kb-2 related-to kb-4 (removed)

$ bs show kb-2
...
(no relations)
```

### Unrelate with custom kind

```
$ bs unrelate kb-7 --uni designed-by,kb-2
Unrelated: kb-7 designed-by kb-2 (removed)
```

### Reopen a resolved todo

```
$ bs show kb-0
todo kb-0 (todo_01abc...)
Status: done
...

$ bs reopen kb-0
Reopened todo: kb-0

$ bs show kb-0
todo kb-0 (todo_01abc...)
Status: open
...
```

### Reopen an archived note

```
$ bs show kb-1
note kb-1 (note_01xyz...)
Status: archived
...

$ bs reopen kb-1
Reactivated note: kb-1

$ bs show kb-1
note kb-1 (note_01xyz...)
Status: active
...
```

### Reopen a non-terminal item (error)

```
$ bs reopen kb-2
Error: kb-2 is not in a terminal state (status: open)
```

### List filtered by relation

Starting state: kb-1, kb-2, kb-6 all depend-on kb-5. kb-6 is done.

```
$ bs list --depends-on kb-5
kb-1  todo  open         Refactor error types
kb-2  todo  in-progress  Update API client
kb-6  todo  done         Add retry tests

$ bs list todo --status open --depends-on kb-5
kb-1  todo  open  Refactor error types
```

### List filtered by custom relation kind

```
$ bs list --uni designed-by,kb-2
kb-7  todo  open  Implement caching layer
kb-9  todo  open  Add cache invalidation
```

### Transitive dependency listing

Starting state: kb-1 depends-on kb-5; kb-10 depends-on kb-1.

```
$ bs list --depends-on kb-5 --transitive
kb-1   todo  open  Refactor error types
kb-10  todo  open  Migrate callers to new error types
```

### Transitive with multiple filters (error)

```
$ bs list --depends-on kb-5 --related-to kb-3 --transitive
Error: --transitive requires exactly one relation filter
```

### Garbage collection dry run

Configuration: max age is 14 days. kb-7 is a done todo resolved 20 days ago.
kb-8 is an archived note archived 20 days ago, related-to kb-7. Neither has
relations to non-terminal items.

```
$ bs gc --dry-run
Would remove 2 item(s):
  kb-7  todo  done      Fix old bug        (resolved 20 days ago)
  kb-8  note  archived  Old research       (archived 20 days ago)
  Plus 1 relation(s) between removed items.
```

```
$ bs gc
Removed 2 item(s), 1 relation(s).
```

### GC retains items anchored transitively by non-terminal relations

Starting state: kb-7 (done, 20 days old) is related-to kb-8 (done, 20 days
old) which is related-to kb-3 (open todo). Max age is 14 days.

```
$ bs gc --dry-run
Would remove 0 item(s):
  Retained: kb-7 (done, 20 days old) — reachable from non-terminal item kb-3
  Retained: kb-8 (done, 20 days old) — reachable from non-terminal item kb-3
```

After kb-3 is also resolved and ages past the threshold, all three become
eligible.

### Automatic GC on regular commands

Configuration: max age is 14 days. kb-7 was resolved 20 days ago and no
item reachable from it is non-terminal.

```
$ bs list
kb-1  todo  open    Fix timeout handling
kb-3  todo  open    Refactor DB module
```

kb-7 does not appear — it was cleaned up automatically during open.

### Sort with available

```
$ bs list --available --sort updated
kb-3  todo  open  Refactor DB module
kb-1  todo  open  Fix timeout handling
```

### Sort with count (error)

```
$ bs list --sort updated --count
Error: --sort cannot be combined with --count
```

### Count statistics

```
$ bs list --count
3 open todos, 1 in-progress todo, 2 done todos
4 active notes, 1 archived note

$ bs list todo --count
3 open, 1 in-progress, 2 done

$ bs list --available --count
2 available todos
```

## Constraints

- **JSONL format will change.** Adding timestamps requires `created_at` and
  `updated_at` fields in todo and note JSONL records. Since we are
  pre-release, a breaking format change is acceptable. The `entity_record`
  type, JSONL serializer/parser, and `import` functions all change.

- **Existing CLI commands must continue to work.** New features add commands
  and flags; existing command signatures and behavior are unchanged except
  where noted (`show` gains timestamp lines, `list` gains new flags, JSON
  output gains timestamp fields).

- **No new runtime dependencies.** Timestamps use `Unix.gettimeofday` or
  equivalent. GC and graph traversal are implemented in application code.

- **Agent-first design.** All new commands support `--json` output. Error
  messages are specific and machine-parseable (e.g., "blocked by kb-3", not
  "operation failed").

- **No interactive prompts.** All input comes from arguments, flags, and
  stdin, consistent with the existing design.

- **Delete JSON output uses a flat structure.** Each deleted item is an
  entry in a `deleted` array with its type, niceid, and a list of removed
  relations. This matches the existing `relate` command's flat list pattern.
  (Resolved from open question 6.)

- **Timestamps use ISO 8601 in all JSON contexts** (JSONL file, `--json`
  output) and a human-readable `YYYY-MM-DD HH:MM:SS UTC` format in text
  output. Internal storage is integer seconds since Unix epoch. (Resolved
  from open question 4.)

## Open Questions

1. **Niceid gaps after GC.** GC deletes items and their niceid entries, but
   the niceid allocator always takes `MAX(niceid) + 1`. This means deleted
   niceids are never reused, and over time gaps accumulate (e.g., kb-0,
   kb-3, kb-7 with nothing in between). This is consistent with the
   append-only nature of the existing design and is acceptable for the
   expected scale, but should be noted as a known behavior. *No action
   needed unless scale assumptions change.*

## Approach

The 28 requirements decompose into a dependency chain: timestamps are
infrastructure that GC depends on; repository delete operations are
infrastructure that delete, unrelate, and GC depend on; graph traversal is
shared between GC and `list --transitive`. Rather than presenting multiple
competing approaches, this section describes the single natural
decomposition with its key design decisions. The requirements are
prescriptive enough — particularly around layering (service-layer
timestamps, application-level BFS) — that the genuine choices are within
the approach, not between approaches.

### Implementation order

The features form a dependency DAG:

```
1. Timestamps         (infrastructure — no dependencies)
2. Repository ops     (infrastructure — no dependencies)
3. Reopen             (depends on 1)
4. Delete             (depends on 1, 2)
5. Unrelate           (depends on 2)
6. Graph traversal    (depends on 2)
7. List filtering     (depends on 6)
8. Statistics         (no dependencies)
9. GC                 (depends on 1, 4, 6)
```

Steps 1 and 2 can proceed in parallel. Steps 3–5 and 8 are independent of
each other once their prerequisites are met. Steps 7 and 9 come last.
Each step is independently testable and shippable.

### 1. Timestamps — fields on the data types

Add `created_at` and `updated_at` as `int` fields (Unix epoch seconds) to
both `Data.Todo.t` and `Data.Note.t`:

```ocaml
(* lib/data/todo.ml — after change *)
type t = {
  id         : id;
  niceid     : Identifier.t;
  title      : Title.t;
  content    : Content.t;
  status     : status;
  created_at : int;
  updated_at : int;
}
```

The `make` constructor gains two parameters:

```ocaml
val make : id -> Identifier.t -> Title.t -> Content.t -> status ->
           created_at:int -> updated_at:int -> t
```

New accessors `created_at : t -> int` and `updated_at : t -> int`. A
single updater `with_updated_at : t -> int -> t` for the service layer.
The existing `with_status`, `with_title`, `with_content` do not touch
timestamps (requirement 2). `pp`/`show` include timestamp fields in
the derived representation.

**Where timestamps are set.** `created_at` and `updated_at` are both set
to `now` at creation time. The service layer sets `updated_at` after the
existing no-op detection passes — the sequence in `Mutation_service.update`
becomes:

```
1. find item
2. apply field changes (with_status, with_title, with_content)
3. _todo_changed / _note_changed → if no-op, return error
4. set updated_at to now (with_updated_at)
5. persist via repo.update
```

This preserves the existing no-op logic unchanged. The clock source is
`Unix.gettimeofday` (already used in `uuidv7.ml`), truncated to `int`.

**What changes for consumers.** Every call site that constructs a `Todo.t`
or `Note.t` via `make` gains two arguments. This affects:

- `Repository.Todo.create` / `import` and `Repository.Note.create` / `import`
- All unit tests that construct todos/notes directly
- `Sync_service.force_rebuild` (passes timestamps from JSONL records)

The `create` functions generate `now` internally. The `import` functions
accept timestamps from JSONL data.

**SQLite schema.** Two new columns per table:

```sql
CREATE TABLE IF NOT EXISTS todo (
  id TEXT PRIMARY KEY,
  niceid TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

Since `force_rebuild` drops and recreates tables, no migration is needed —
the next rebuild adds the columns and populates them from JSONL data.
For existing JSONL files without timestamps, the rebuild assigns `now` as a
synthetic value (requirement 6).

**JSONL format.** Two new fields per todo/note record:

```json
{"type":"todo","id":"todo_01abc...","title":"...","content":"...","status":"open",
 "created_at":"2026-03-15T14:30:00Z","updated_at":"2026-03-15T14:30:00Z"}
```

The JSONL serializer writes ISO 8601; the parser reads ISO 8601 and
converts to `int` epoch seconds. Formatting and parsing use a small
`Timestamp` helper module in the Data layer, built on `Unix.gmtime` /
`Unix.mktime` and `Printf.sprintf` / `Scanf.sscanf` — no new
dependencies. A datetime library would be warranted if we were doing
arithmetic, timezone handling, or duration formatting, but epoch-second
storage with ISO 8601 at the boundary is simple enough for stdlib.

The `entity_record` type gains timestamp fields:

```ocaml
type entity_record =
  | Todo of { id; title; content; status; created_at: int; updated_at: int }
  | Note of { id; title; content; status; created_at: int; updated_at: int }
  | Relation of Data.Relation.t
```

**What changes for tests.** Every `Data.Todo.make` and `Data.Note.make`
call in tests gains `~created_at:0 ~updated_at:0` (or a test helper that
defaults them). Repository and service tests that create items via the
service layer are unaffected — the service sets timestamps internally.
JSONL round-trip tests gain timestamp fields.

### 2. Repository delete operations

Three new repository functions, corresponding to requirements 27–28.

**`Repository.Relation.delete`** — removes a single relation by composite
key, with bidirectional reverse-aware lookup:

```ocaml
val delete :
  t -> source:Data.Uuid.Typeid.t -> target:Data.Uuid.Typeid.t ->
  kind:Data.Relation_kind.t -> bidirectional:bool ->
  (unit, error) result
```

The implementation first tries `DELETE FROM relation WHERE source = ?
AND target = ? AND kind = ?`. If `bidirectional` is true and no row was
affected, it tries the reverse `(target, source, kind)`. Returns
`Not_found` (new error variant) if neither direction exists.

**`Repository.Relation.delete_by_entity`** — removes all relations
involving a TypeId:

```ocaml
val delete_by_entity :
  t -> Data.Uuid.Typeid.t -> (int, error) result
```

Uses `DELETE FROM relation WHERE source = ? OR target = ?`. Returns the
number of deleted rows.

**`Repository.Niceid.delete`** — removes a single niceid mapping:

```ocaml
val delete : t -> Data.Uuid.Typeid.t -> (unit, error) result
```

Uses `DELETE FROM niceid WHERE typeid = ?`.

### 3. Reopen

A new `reopen` function in `Mutation_service`:

```ocaml
val reopen : t -> identifier:string -> (Item_service.item, Item_service.error) result
```

The implementation resolves the identifier, checks terminal state (done
for todos, archived for notes), and delegates to `update` with the
appropriate initial status:

```
Todo (Done) → update ~status:"open"
Note (Archived) → update ~status:"active"
Todo (Open | In_Progress) → Validation_error "not in terminal state"
Note (Active) → Validation_error "not in terminal state"
```

This mirrors the structure of `resolve` and `archive` — find, validate
type/state, delegate to `update`.

A new `Cmd_reopen` module in `bin/` (following `cmd_resolve.ml` pattern,
~45 lines). Registered in `main.ml`.

### 4. Delete

A new `delete` function in a `Delete_service` module (or added to
`Mutation_service`, though the cascade logic is complex enough to warrant
its own module):

```ocaml
val delete :
  t -> identifier:string -> force:bool ->
  (delete_result, delete_error) result

val delete_many :
  t -> identifiers:string list -> force:bool ->
  (delete_result list, delete_error) result

type delete_result = {
  niceid      : Data.Identifier.t;
  entity_type : string;
  relations_removed : int;
}

type delete_error =
  | Blocked_dependency of { niceid : string; dependents : string list }
  | Service_error of Item_service.error
```

The cascade sequence for a single item, within a transaction:

```
1. resolve identifier → item (typeid, niceid, type)
2. if not force:
     find relations where this item is a blocking target of a non-terminal source
     if any → Error (Blocked_dependency ...)
3. delete_by_entity typeid → relation table cleanup
4. delete niceid mapping → niceid table cleanup
5. delete item → todo or note table cleanup
```

For `delete_many`, each item is processed independently within the same
transaction. If any item fails the blocking check (and `--force` is not
set), the entire batch fails before any deletion occurs.

A new `Cmd_delete` module in `bin/` (~65 lines). Accepts multiple
positional identifiers (like `show`) and a `--force` flag.

### 5. Unrelate

A new `unrelate` function added to `Relation_service`:

```ocaml
val unrelate :
  t -> source:string -> specs:relate_spec list ->
  (unrelate_result list, Item_service.error) result

type unrelate_result = {
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  kind          : Data.Relation_kind.t;
  bidirectional : bool;
}
```

The implementation mirrors `relate_many`: resolve source and targets,
validate kinds, then call `Repository.Relation.delete` for each. The
bidirectional flag is passed through so the repository delete can check
the reverse direction.

A new `Cmd_unrelate` module in `bin/` (~55 lines). Reuses the shared
relation flags from `cmdline_common.ml`.

### 6. Graph traversal — shared module

A new `Graph_service` module in `lib/service/` providing reachability
queries over the relation graph. Used by both GC (transitive anchoring)
and `list --transitive`.

```ocaml
(* lib/service/graph_service.mli *)

type t

val init : Repository.Root.t -> t

(** [reachable_from t ~typeid ~kind ~direction] returns all TypeIds
    reachable from [typeid] by following relations of the given [kind]
    in the given [direction]. Uses BFS. Follows only the specified kind
    if [kind] is [Some _]; follows all kinds if [None].

    [direction] controls which end of each relation is followed:
    - [`Outgoing] follows source → target
    - [`Incoming] follows target → source
    - [`Any] follows both directions (for GC anchoring) *)
val reachable_from :
  t ->
  typeid:Data.Uuid.Typeid.t ->
  kind:Data.Relation_kind.t option ->
  direction:[ `Outgoing | `Incoming | `Any ] ->
  (Data.Uuid.Typeid.t list, Item_service.error) result

(** [connected_component t ~typeid] returns all TypeIds in the same
    connected component as [typeid], following all relation kinds in
    both directions. Used by GC transitive anchoring. *)
val connected_component :
  t ->
  typeid:Data.Uuid.Typeid.t ->
  (Data.Uuid.Typeid.t list, Item_service.error) result
```

The implementation uses application-level BFS, consistent with the
existing `find_blockers` pattern. Each BFS step calls
`Repository.Relation.find_by_source` and/or `find_by_target` and
collects unseen TypeIds in a visited set.

**Why application-level BFS, not recursive CTE.** The codebase has no
recursive CTEs (background section). Application-level traversal is more
testable (can mock repositories), matches the existing pattern, and for
the expected graph sizes (tens to hundreds of nodes) performs equivalently.
If the GC benchmark (requirement 24) shows this is too slow, a recursive
CTE can be substituted as an optimization without changing the API.

**`list --transitive` uses `reachable_from`.** For
`bs list --depends-on kb-5 --transitive`:

```
1. resolve kb-5 → typeid
2. reachable_from ~typeid ~kind:(Some "depends-on") ~direction:`Incoming
   → set of TypeIds that transitively depend on kb-5
3. resolve each TypeId to an item
4. apply remaining filters (type, status)
5. sort and return
```

**GC uses `connected_component`.** For each age-eligible terminal item:

```
1. connected_component ~typeid → all reachable items
2. if any item in the component is non-terminal → retain all
3. if all items in the component are terminal and age-eligible → remove all
```

The GC algorithm groups items into connected components first, then decides
per-component. This avoids re-traversing shared components.

### 7. List query expansion

The `list` function's signature is growing: it currently takes
`~entity_type ~statuses ~available`, and needs `~sort ~asc ~count` plus
relation filter parameters. Rather than an explosion of optional
parameters, introduce a query spec record:

```ocaml
(* lib/service/query_service.mli *)

type sort_order = Sort_created | Sort_updated

type relation_filter = {
  target    : string;  (* niceid or TypeId of the item to filter by *)
  kind      : string;
  direction : [ `Outgoing | `Incoming ];
}

type list_spec = {
  entity_type : string option;
  statuses    : string list;
  available   : bool;
  sort        : sort_order option;
  ascending   : bool;
  count_only  : bool;
  relation_filters : relation_filter list;
  transitive       : bool;
}

type list_result =
  | Items of item list
  | Counts of { todos : (string * int) list; notes : (string * int) list }

val list : t -> list_spec -> (list_result, error) result
```

The `list` function validates flag interactions (requirement 19) upfront:

```
if available && statuses <> [] → error
if sort <> None && count_only → error
if transitive && relation_filters = [] → error
if transitive && List.length relation_filters > 1 → error
```

Then dispatches to the appropriate code path:
- `count_only` → fetch items, group by type and status, return counts
- `relation_filters` present → resolve targets, use graph service
  (`reachable_from` if transitive, direct relation lookup if not),
  intersect with type/status-filtered items
- Otherwise → existing fetch + merge + sort logic

The sort comparator is parameterized:

```ocaml
let sort_items ~sort ~ascending items =
  let compare = match sort with
    | None -> fun a b -> Int.compare (raw_id_of_item a) (raw_id_of_item b)
    | Some Sort_created -> fun a b -> Int.compare (created_at_of a) (created_at_of b)
    | Some Sort_updated -> fun a b -> Int.compare (updated_at_of a) (updated_at_of b)
  in
  let cmp = if ascending then compare else fun a b -> compare b a in
  List.sort cmp items
```

Default sort direction is descending for timestamp sorts (requirement 5),
ascending for niceid sort (existing behavior).

**What changes for consumers.** `Kb_service.list` changes from individual
parameters to a `list_spec` record. `Cmd_list.run` constructs the record
from CLI flags. The existing `Kb_service.list` callers (just `cmd_list.ml`)
update to the new signature.

### 8. Statistics (--count)

Implemented as part of the list query expansion (step 7). When
`count_only = true`, the list function fetches items through the normal
path, then groups and counts by type and status instead of returning the
full list. The CLI formats counts as text or JSON.

The text format:

```
3 open todos, 1 in-progress todo, 2 done todos
4 active notes, 1 archived note
```

The JSON format:

```json
{"ok": true, "counts": {
  "todos": {"open": 3, "in-progress": 1, "done": 2},
  "notes": {"active": 4, "archived": 1}
}}
```

### 9. Garbage collection

A new `Gc_service` module in `lib/service/`:

```ocaml
(* lib/service/gc_service.mli *)

type t

type gc_result = {
  items_removed    : int;
  relations_removed : int;
}

type gc_item = {
  niceid      : Data.Identifier.t;
  entity_type : string;
  title       : Data.Title.t;
  age_days    : int;
}

val init : Repository.Root.t -> t

(** [collect t ~max_age_seconds ~now] identifies items eligible for
    removal. Returns the items grouped by connected component. *)
val collect :
  t -> max_age_seconds:int -> now:int ->
  (gc_item list, Item_service.error) result

(** [run t ~max_age_seconds ~now] removes eligible items and their
    relations. Returns counts of removed items and relations. *)
val run :
  t -> max_age_seconds:int -> now:int ->
  (gc_result, Item_service.error) result
```

The GC algorithm:

```
1. list all terminal items (done todos + archived notes)
2. filter to items where (now - updated_at) > max_age_seconds
3. for each age-eligible item, compute connected_component
4. for each component:
   a. if every item in the component is terminal → mark for removal
   b. if any item is non-terminal → retain all
5. for each item marked for removal:
   a. delete_by_entity (relations)
   b. delete niceid mapping
   c. delete item
```

Step 3 uses `Graph_service.connected_component`. Components are
deduplicated (items in the same component are only traversed once).

**Integration with `open_kb`.** The GC hook is added to
`Kb_service.open_kb`, after `rebuild_if_needed`:

```ocaml
let open_kb () =
  ...
  let* () = Sync_service.rebuild_if_needed sync in
  let* () = _run_gc_if_configured root sync in
  let t = { (init root) with sync = Some sync } in
  Ok (root, t)
```

`_run_gc_if_configured` reads `gc_max_age` from config. If absent, GC is
skipped. If present, it calls `Gc_service.run` and flushes if anything
was removed.

**`bs gc` command.** A new `Cmd_gc` module in `bin/` (~80 lines) with:

- `bs gc` — run GC explicitly (regardless of whether auto-GC just ran)
- `bs gc --dry-run` — show what would be removed
- `bs gc --set-max-age 14d` — set the max age policy
- `bs gc --show-max-age` — display current policy

**Performance benchmark.** A new scenario in `test-perf/perf_scenarios.ml`
following the existing pattern:

```ocaml
val scenario_gc : samples:int -> unit
```

Populates a KB with 500 items and 1000 relations, sets half the items to
terminal with old timestamps, and measures `Gc_service.run` latency.
The performance gate is < 50ms (requirement 24).

### Limitations

- **No relation-type-aware GC.** GC treats all relation kinds equally for
  anchoring. A `depends-on` relation and a `related-to` relation both
  anchor terminal items. This is by design (transitive anchoring), but
  means a stale `related-to` link can prevent cleanup.

- **No incremental GC.** Every GC run recomputes connected components from
  scratch. For the expected scale this is fine. The "last GC time"
  optimization (requirement 24) would skip redundant runs, not make
  individual runs faster.

- **No niceid compaction.** Deleted niceids create gaps that are never
  reclaimed. This is the documented open question.

## Design Decisions

1. **Timestamps live in the data types, not in a wrapper.** Adding
   `created_at` and `updated_at` directly to `Todo.t` and `Note.t` is more
   invasive (every `make` call site changes) but cleaner: the types fully
   describe the entity, accessors work uniformly, and there's no
   wrapper/envelope to thread through the system. The alternative — a
   `Timestamped.t` wrapper that pairs an item with its timestamps — would
   avoid touching `make` call sites but add indirection at every consumer.
   Given that the project is pre-release and test updates are mechanical,
   the direct approach is preferred.

2. **`updated_at` is a service concern, not a data concern.** The `with_*`
   updaters on the data types do not touch `updated_at`. The service layer
   sets it explicitly after no-op detection passes. This keeps the data
   layer pure (no clock dependency) and preserves the existing no-op
   detection logic without modification. The tradeoff: callers that bypass
   the service layer and use repositories directly must remember to set
   `updated_at` — but this is already true for other service-layer
   invariants (e.g., blocking checks for claim).

3. **Application-level BFS for graph traversal.** Consistent with
   `find_blockers`, testable without SQLite, sufficient for expected scale.
   A recursive CTE is available as an optimization if the GC benchmark
   fails, but the API (`reachable_from`, `connected_component`) is
   implementation-agnostic — switching to a CTE would not change the
   service interface.

4. **Query spec record for list.** The `list` function's growing parameter
   list is replaced with a record type. This is more idiomatic for optional
   parameters in OCaml (named fields with defaults), makes flag interaction
   validation self-contained, and is easier to extend in the future.

5. **Delete as service-layer orchestration, not SQL cascade.** The delete
   cascade (item + relations + niceid) is coordinated at the service layer
   within a transaction, not via SQL foreign keys or triggers. This matches
   the codebase pattern: repositories are thin CRUD wrappers, and business
   logic (like checking for blocking dependencies before delete) lives in
   services. SQL cascades would hide logic in the schema and make it harder
   to implement the `--force` guard.

6. **GC hooks into `open_kb`, not `_with_flush`.** Running GC during
   `open_kb` means every command sees a clean state. The alternative —
   wrapping every command — would require changes to every `Cmd_*.ml` file
   or a new CLI-level wrapper. Since `open_kb` already performs
   `rebuild_if_needed`, adding GC there is consistent and requires changes
   in only one place.

## Rejected Alternatives

- **Timestamps as a separate table.** A `timestamps` table with
  `(typeid, created_at, updated_at)` would avoid changing the entity types
  and schemas, but would require a join on every read and complicate the
  JSONL format (timestamps would either be separate records or inlined
  at serialization time). The complexity outweighs the benefit of avoiding
  schema changes.

- **Recursive CTE for graph traversal.** SQLite supports
  `WITH RECURSIVE`, which could implement `reachable_from` and
  `connected_component` in a single query. This was rejected for the
  initial implementation because: (a) no existing CTE usage in the
  codebase, (b) application-level BFS is more testable, (c) the expected
  graph sizes don't warrant the optimization. The API is designed so a CTE
  implementation can be substituted later if the GC benchmark warrants it.

- **Lazy GC (on first write, not on open).** Running GC only on write
  operations (via `_with_flush`) would avoid the cost on read-only
  commands. But it means `bs list` could show stale items that should have
  been cleaned up, which undermines the "automatic cleanup" requirement.
  GC on open ensures a clean view regardless of the operation.

## Consequences and Trade-offs

**Migration path.** The approach is fully incremental. Each step (1–9)
produces a working system. Steps 1 and 2 are the only breaking changes
(new `make` parameters, new JSONL fields), and since we're pre-release,
there are no external consumers to migrate. Steps 3–9 add new features
without changing existing interfaces.

**Test impact.** Step 1 (timestamps) has the largest test impact: every
`Data.Todo.make` and `Data.Note.make` call site in tests gains two
parameters. This is mechanical but tedious. Steps 2–9 add new tests
without modifying existing ones (except snapshot updates for `show` output
gaining timestamp lines).

**Type safety.** Timestamps as `int` fields on the data types are
type-safe at the OCaml level — they're part of the record, cannot be
forgotten, and are checked by the compiler. The alternative (a
`Timestamped.t` wrapper) would also be type-safe but adds a level of
indirection. One area where type safety is weaker: `int` seconds are not
distinguished from other `int` values. A `Timestamp.t` data type could
encapsulate this, but the requirements don't call for timestamp
validation (any non-negative integer is valid), so the encapsulation
would add ceremony without preventing bugs.

**Performance.** The GC scan on every `open_kb` is the main performance
concern. For the expected scale (tens of items), it's negligible. The
benchmark requirement (24) provides a concrete gate: if GC takes > 50ms
at 500 items / 1000 relations, a "skip if recently run" optimization is
triggered. The `connected_component` BFS is O(V + E) where V is the
number of terminal items and E is their relations — not the entire
knowledge base.

**Extensibility.** The `list_spec` record and `Graph_service` API are
designed for extension. New list filters add fields to the record. New
graph queries add functions to the service. The GC algorithm can be
tuned (e.g., kind-specific anchoring rules) by modifying `Gc_service`
without changing the graph traversal layer.

## Requirement Coverage

| Req | Description | Coverage |
|-----|-------------|----------|
| 1 | Timestamps on items | Step 1: fields on Todo.t and Note.t |
| 2 | Service-layer updated_at | Step 1: set after no-op check in Mutation_service |
| 3 | Timestamps in show | Step 1: Cmd_show gains Created/Updated lines |
| 4 | Timestamps in list JSON only | Step 1: Cmd_list JSON output gains fields |
| 5 | --sort created/updated, --asc | Step 7: list_spec.sort + ascending |
| 6 | JSONL round-trip | Step 1: entity_record, serializer, parser |
| 7 | bs delete | Step 4: Delete_service + Cmd_delete |
| 8 | Cascade delete (relations + niceid) | Step 4: orchestrated in transaction |
| 9 | --force for blocking deps | Step 4: Blocked_dependency error + force flag |
| 10 | Batch delete | Step 4: delete_many |
| 11 | bs unrelate | Step 5: Relation_service.unrelate + Cmd_unrelate |
| 12 | Bidirectional unrelate | Step 5: Relation.delete tries reverse direction |
| 13 | bs reopen (done → open) | Step 3: Mutation_service.reopen |
| 14 | bs reopen (archived → active) | Step 3: same function, type-dispatched |
| 15 | list --depends-on / --related-to / --uni / --bi | Step 7: list_spec.relation_filters |
| 16 | --transitive | Step 7: list_spec.transitive + Graph_service.reachable_from |
| 17 | Relation filters compose with type/status | Step 7: intersection in list implementation |
| 18 | --transitive requires one filter | Step 7: validated in list |
| 19 | Flag interaction rules | Step 7: validated upfront in list |
| 20 | bs gc | Step 9: Gc_service + Cmd_gc |
| 21 | gc_max_age config | Step 9: Config table key |
| 22 | Transitive anchoring | Step 9: connected_component per component |
| 23 | GC on open_kb | Step 9: hook in Kb_service.open_kb |
| 24 | GC benchmark | Step 9: test-perf scenario |
| 25 | --dry-run | Step 9: Gc_service.collect (no removal) |
| 26 | --count | Step 8: list_spec.count_only |
| 27 | Relation delete + delete_by_entity | Step 2: Repository.Relation |
| 28 | Niceid delete | Step 2: Repository.Niceid |

## Recommendation

Implement the approach as described, in dependency order (steps 1–9). The
approach is conservative — it follows every existing codebase pattern, uses
no new techniques (application-level BFS, service-layer orchestration,
config key-value pairs), and is fully incremental.

The one area with genuine risk is GC performance at scale (requirement 24).
The mitigation is explicit: benchmark first, optimize only if the gate
fails. The optimization (skip GC if recently run) is simple and does not
require architectural changes — it adds a config key check before the GC
scan.

Steps 1–2 should be implemented first as they unblock everything else.
Steps 3, 5, and 8 are small and independent — good candidates for quick
wins. Steps 4, 6, 7, and 9 are the largest and most interconnected, but
the dependency ordering ensures each builds on tested foundations.
