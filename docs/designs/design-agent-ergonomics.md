# Design: Agent Ergonomics — Inline Relations

## Problem Statement

When an agent uses `bs` to create a set of related items — for example, an
implementation plan with a parent note and dependent task todos — it must
issue a separate `bs relate` call for every relation after creating each item.
In a recent session that created 1 note, 11 todos, and 27 relations, 27 of
39 total invocations were `relate` calls that could have been folded into the
preceding `add` commands. The `relate` command itself also accepts only one
relation per invocation, so wiring up a dependency graph requires one CLI call
per edge.

This friction compounds: each invocation pays startup cost, and the
create-then-relate pattern forces the agent to predict or parse niceids
between steps. Reducing invocation count for the common case of "create an
item and immediately relate it" and "relate one item to several others" would
materially improve agent throughput and reduce fragile niceid-prediction
chains.

## Background

### Architecture overview

The codebase follows a four-layer architecture (Data → Control →
Repository → Service), with a thin CLI layer in `bin/` that handles
argument parsing and output formatting. The layers relevant to this
design are:

- **`bin/cmd_add.ml`** (98 lines) — cmdliner terms for `add todo` and
  `add note`. Parses `TITLE` and `--json`, reads content from stdin,
  calls `Kb_service.add_todo` / `Kb_service.add_note`, formats the
  result.
- **`bin/cmd_relate.ml`** (85 lines) — cmdliner terms for `relate`.
  Parses `SOURCE`, one of `--depends-on`/`--related-to`/`--uni`/`--bi`,
  and `--json`. Calls `Kb_service.relate`, formats the result.
- **`lib/service/kb_service.ml`** (158 lines) — top-level façade that
  delegates to sub-services and wraps each mutating operation in
  `_with_flush` (mark dirty → execute → flush JSONL).
- **`lib/service/note_service.ml`** (18 lines) /
  **`lib/service/todo_service.ml`** (18 lines) — thin wrappers that
  delegate to `Repository.Note.create` / `Repository.Todo.create` and
  map repository errors to service errors.
- **`lib/service/relation_service.ml`** (50 lines) — resolves source
  and target identifiers via `Item_service.find`, validates the relation
  kind via `Parse.relation_kind`, constructs a `Data.Relation.t`, and
  calls `Repository.Relation.create`.
- **`lib/service/item_service.ml`** (82 lines) — identifier resolution:
  attempts niceid lookup across both todo and note repos, falls back to
  TypeId parsing.

### How `add` works today

The `add todo` CLI path (`cmd_add.ml:run_todo`):

1. `App_context.init()` opens the KB (finds git root, opens SQLite,
   rebuilds from JSONL if needed).
2. Reads stdin via `Io.read_all_stdin()`.
3. Constructs `Title.make` and `Content.make` (validation; raises
   `Invalid_argument` on failure).
4. Calls `Kb_service.add_todo service ~title ~content ()`.
5. `Kb_service.add_todo` wraps the call in `_with_flush`, which: marks
   the sync as dirty, calls `Todo_service.add` (which delegates to
   `Repository.Todo.create`), then flushes to JSONL.
6. On success, prints `"Created todo: %s (%s)\n"` with niceid and
   TypeId. On error, exits with an error message.

`add note` follows the same pattern through `Note_service.add`.

The add functions return a `Data.Todo.t` or `Data.Note.t` — the created
entity, including its assigned niceid and TypeId. They do **not** return
any relation information, because no relations are created.

### How `relate` works today

The `relate` CLI path (`cmd_relate.ml:run`):

1. Parses exactly one of `--depends-on`, `--related-to`, `--uni`, or
   `--bi` from the command line. The `run` function pattern-matches the
   four `option` values to extract a single `(target, kind,
   bidirectional)` triple. If zero or more than one flag is provided,
   it exits with an error.
2. Calls `Kb_service.relate service ~source ~target ~kind
   ~bidirectional`.
3. `Kb_service.relate` wraps the call in `_with_flush`.
4. `Relation_service.relate` resolves source and target via
   `Item_service.find`, validates the kind string via
   `Parse.relation_kind`, constructs a `Data.Relation.t`, and calls
   `Repository.Relation.create`.
5. Returns a `relate_result` record containing the relation, source
   niceid, and target niceid.

The key constraint is in step 1: `cmd_relate.ml` uses `Arg.opt (some
string) None` for each flag, producing `string option` values. The
pattern match enforces exactly-one semantics — this is CLI-level
validation, not service-level.

### Cmdliner multi-value support

The `relate` command currently uses `Arg.opt` for each relation flag,
which accepts at most one occurrence. Cmdliner provides `Arg.opt_all`
for repeated flags:

```ocaml
val opt_all : ?vopt:'a -> 'a conv -> 'a list -> info -> 'a list t
```

`opt_all` returns a `'a list` with one element per flag occurrence on
the command line, in order. It composes with all converters — including
`Arg.pair`, which is already used for `--uni` and `--bi`:

```ocaml
(* Current: accepts one --uni *)
Arg.(value & opt (some (pair ~sep:',' string string)) None
  & info [ "uni" ] ...)

(* With opt_all: accepts many --uni *)
Arg.(value & opt_all (pair ~sep:',' string string) []
  & info [ "uni" ] ...)
```

For `--depends-on` and `--related-to`, which take a single string
target, the conversion is straightforward: `opt (some string) None`
becomes `opt_all string []`.

The comma-separated alternative (e.g. `--related-to kb-1,kb-2`) would
require a custom converter using `Arg.list ~sep:',' string`, which
splits a single argument value at commas. This conflicts with `--uni`
and `--bi`, which already use comma as the separator between KIND and
TARGET (`--uni designed-by,kb-1`). A target containing a comma would be
ambiguous in the `--uni`/`--bi` syntax.

### Output format conventions

**Human-readable `add` output** is a single line:

```
Created todo: kb-0 (todo_01abc...)
```

**Human-readable `relate` output** is a single line per relation:

```
Related: kb-0 depends-on kb-1 (unidirectional)
```

**Human-readable `show` output** displays relations in a structured
block below the item, indented with two spaces:

```
Outgoing:
  depends-on  kb-1  todo  Implement data layer
  depends-on  kb-2  todo  Implement API endpoints
```

Each relation entry in `show` includes the kind, target niceid, target
entity type, and target title — all resolved from the database. The
`show` formatting code lives in `cmd_show.ml` (functions
`format_relation_entry`, `format_relations`, and
`relation_entry_to_json`).

**JSON `add` output** today:

```json
{"ok":true,"type":"todo","niceid":"kb-0","typeid":"todo_01abc..."}
```

**JSON `relate` output** today:

```json
{"ok":true,"source":"kb-0","kind":"depends-on","target":"kb-1",
 "directionality":"unidirectional"}
```

JSON serialization for both commands lives inline in their respective
`cmd_*.ml` files, per the `bin/` conventions.

### The `_with_flush` wrapper

Every mutating `Kb_service` function is wrapped in `_with_flush`, which
marks the sync as dirty, executes the operation, then flushes to JSONL.
Today each `_with_flush` call contains a single repository write. If
`add` needs to create an entity *and* one or more relations, both must
happen within the same `_with_flush` scope so that a single flush covers
all writes.

`_with_flush` does **not** use a SQLite transaction — it calls
`mark_dirty`, runs the callback, and calls `flush`. The
`Sqlite.with_transaction` helper exists in the repository layer but is
not currently used by `_with_flush`. This means there is no built-in
rollback mechanism if relation creation fails after the entity is
already inserted. Atomicity (requirement 7) would need to either use
`Sqlite.with_transaction` or manually delete the created entity on
failure.

### Transaction support

`Repository.Sqlite` provides `with_transaction`:

```ocaml
val with_transaction :
  Sqlite3.db ->
  on_begin_error:(string -> 'e) ->
  (unit -> ('a, 'e) result) ->
  ('a, 'e) result
```

It issues `BEGIN IMMEDIATE`, runs the callback, commits on `Ok`, and
rolls back on `Error` or exception. The underlying `Sqlite3.db` handle
is accessible via `Repository.Root.db`. This function is available but
unused by any current service code.

### Relation data flow

`Relation_service.relate` accepts raw strings for `source`, `target`,
and `kind`, plus a `bidirectional` bool. It resolves the identifiers
internally and returns a `relate_result`:

```ocaml
type relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
}
```

To support multiple relations in one call, the service layer would need
a function that accepts a list of `(target, kind, bidirectional)` tuples
and returns a list of `relate_result` values — or a new composite result
type. The existing `relate` function creates relations one at a time
through `Repository.Relation.create`, which issues individual INSERT
statements.

### Existing patterns for multi-value CLI arguments

No existing command uses `Arg.opt_all`. All optional flags use
`Arg.opt` (single value) or `Arg.flag` (boolean). The `list` command
uses `Arg.pos 0` for the optional entity type and `Arg.opt` for
`--status`. The codebase has no precedent for repeated flags.

However, the pattern would be consistent with cmdliner conventions.
`opt_all` produces a plain `'a list`, so the Term combinator changes
from `const f $ opt_arg` to `const f $ opt_all_arg` with the function
accepting a list instead of an option.

### Test coverage

**Integration tests** for the affected commands:

- `add_todo_expect.ml` (102 lines): 7 tests covering happy path,
  sequential niceids, empty title, empty content, no git repo, no KB,
  and `--json` output.
- `add_note_expect.ml` (102 lines): 7 tests mirroring the todo tests.
- `relate_expect.ml` (124 lines): 9 tests covering `--depends-on`,
  `--related-to`, `--uni`, `--bi`, source not found, target not found,
  duplicate, no git repo, no KB, and `--json` output.
- `workflow_expect.ml` (239 lines): 3 cross-command scenarios that
  exercise create → relate → update → list sequences.

**Unit tests** for the affected services:

- `relation_service_expect.ml` (187 lines): 7 tests covering
  depends-on, related-to, user-defined unidirectional, source not found,
  target not found, invalid kind, duplicate, and bidirectional reverse
  duplicate.
- `note_service_expect.ml` (36 lines): 1 test verifying row
  persistence.
- `todo_service_expect.ml` (46 lines): 2 tests verifying row
  persistence and explicit status.

All tests use ppx_expect. Integration tests invoke the `bs` binary via
`Test_helper.run_bs` and normalize output with `print_result`
(TypeId → `<TYPEID>`, absolute paths → `<DIR>`). Unit tests use
in-memory SQLite databases via `Root.init ~db_file:":memory:"`.

### Observations

1. **The comma separator in `--uni`/`--bi` blocks the comma-separated
   multi-target syntax.** `--uni` and `--bi` already parse their value
   as `pair ~sep:',' string string`, splitting at the first comma. A
   comma-separated list of targets (`--related-to kb-1,kb-2`) would
   require a different separator or a new parsing convention for
   `--uni`/`--bi`. The repeated-flag approach (`--related-to kb-1
   --related-to kb-2`) avoids this conflict entirely.

2. **No existing transaction usage.** `_with_flush` does not wrap its
   callback in a transaction. For requirement 7 (atomicity on `add`
   with inline relations), this is a gap. The transaction infrastructure
   exists in `Repository.Sqlite` but has never been used by the service
   layer. Adding transactional wrapping would be new to the codebase.

3. **`_with_flush` would need to encompass both the entity insert and
   the relation inserts.** Today `add_note` calls `_with_flush` around
   `Note.add`, and `relate` calls `_with_flush` around
   `Relation.relate`. A combined add-with-relations operation would need
   a single `_with_flush` scope that covers both steps, or the flush
   logic would run twice. This argues for a new service function rather
   than calling the existing `add_note` and `relate` in sequence.

4. **`show` already resolves relation metadata (entity type, title,
   niceid).** The `add` output for inline relations will want to display
   similar metadata (scenario 1 shows kind, niceid, type, and title for
   each relation). The resolution logic lives in `Query_service.show`
   and `cmd_show.ml`, which could be reused or extracted.

5. **`Relation_service.relate` takes raw strings and does its own
   resolution.** For inline relations on `add`, the source is the
   just-created entity (already a `Data.Todo.t` or `Data.Note.t` with
   a known TypeId and niceid), not a string that needs resolution. A
   new service function could skip source resolution and accept the
   TypeId directly, avoiding a redundant database lookup.

6. **The `run` function in `cmd_relate.ml` enforces exactly-one
   semantics via pattern matching on four `option` values.** Switching
   to `opt_all` (which returns lists) would change this pattern match
   entirely. The CLI validation logic that currently rejects "zero or
   more than one flag" would become "at least one flag total across all
   four lists."

7. **`cmd_add.ml` handles `run_todo` and `run_note` as separate
   functions with near-identical structure.** Adding inline relation
   flags to both would duplicate the relation-handling logic unless it
   is extracted into a shared helper. The file is currently 98 lines;
   duplicating relation handling in both functions would push it toward
   the 300-line limit.

## Requirements

1. **Inline relations on `add todo` and `add note`.** When creating an item,
   the user can specify one or more relations in the same command. The created
   item becomes the source of each specified relation. This eliminates the
   need for a follow-up `relate` call in the common case.

   *Rationale: this was the single biggest source of unnecessary invocations
   in the observed session — 27 of 39 calls.*

2. **All relation kinds supported inline.** The built-in `--depends-on` and
   `--related-to` flags and the user-defined `--uni KIND,TARGET` and
   `--bi KIND,TARGET` flags must all be available on `add`, with the same
   semantics they have on `relate`. Multiple flags of the same kind (e.g.
   two `--related-to` flags) are permitted.

   *Rationale: limiting inline relations to built-in kinds would force agents
   back to separate `relate` calls for user-defined kinds, splitting the
   workflow for no good reason.*

3. **Multiple relations per `add` call.** A single `add` invocation can
   specify more than one relation, including relations of different kinds.
   Relations are created in the order the flags appear on the command line.
   For example:
   `bs add todo "Title" --related-to kb-2 --depends-on kb-5 --related-to kb-3`

   *Rationale: plan-creation workflows typically relate each new item to both
   a parent note and a predecessor task. Ordering is determined by `opt_all`,
   which preserves command-line order.*

4. **Multiple relations per `relate` call.** A single `relate` invocation can
   create more than one relation from the same source, including relations of
   different kinds and multiple flags of the same kind. Relations are created
   and reported in flag order. At least one relation flag must still be
   provided; zero flags is an error.

   *Rationale: wiring up a dependency graph after the fact still requires
   many calls; multi-relation `relate` reduces that to one call per source
   item.*

5. **Human-readable `add` output lists each inline relation.** When `add`
   creates inline relations, the output prints the "Created" line followed by
   one indented line per relation. Each line shows the relation kind, the
   target's niceid, the target's entity type (`todo` or `note`), and the
   target's title — matching the layout used by `show`. Relations are listed
   in the order they were created (flag order).

   *Refined after codebase analysis: scenario 1 commits to showing entity
   type and title, not just kind and niceid. This requires the service to
   return richer result data than the current `relate_result` (which carries
   niceid but not entity type or title). The resolution logic already exists
   in `Query_service.show` and `cmd_show.ml`.*

6. **JSON `add` output includes inline relations.** When `add --json` creates
   inline relations, the response includes a `relations` array containing one
   object per relation created. Each object carries at minimum: `kind`,
   `target` (niceid), `directionality`, `target_type`, and `target_title`.
   The array is empty when no relation flags were provided, preserving the
   existing `add --json` format for callers that do not use inline relations.

   *Refined after codebase analysis: the JSON must carry entity type and
   title to match the human-readable output (requirement 5). An empty array
   when no relations are given avoids changing the meaning of existing output.*

7. **`add` with inline relations is atomic.** If any relation target does not
   exist or any relation is invalid, the command fails with an error and
   neither the item nor any relation is created.

   *Rationale: agents chain commands based on success/failure; a partially
   created item would leave the knowledge base in an unexpected state.*

   *Constraint: atomicity requires wrapping both the entity insert and all
   relation inserts in a single `Sqlite.with_transaction` call. This is the
   first use of transactions in the service layer.*

8. **`relate` with multiple relations is atomic.** If any target does not
   exist or any relation is invalid, no relations are created. The source
   item is unaffected.

   *Constraint: same as requirement 7 — requires `Sqlite.with_transaction`
   around all relation inserts for the call.*

9. **`relate --json` uses an envelope format.** The JSON output for `relate`
   is always `{"ok":true,"relations":[...]}` where each element is a relation
   object with `source`, `kind`, `target`, and `directionality`. This replaces
   the existing flat-object format. The change is acceptable because there are
   no current callers of `relate --json`.

## Scenarios

### Scenario 1: Create a todo with inline relations

Starting state: `kb-0` is a note (design document), `kb-1` is a todo.

```
$ echo "Implement the cache invalidation strategy" \
    | bs add todo "Implement cache invalidation" --related-to kb-0 --depends-on kb-1
Created todo: kb-2 (todo_01abc...)
  related-to  kb-0  note  Design: cache strategy
  depends-on  kb-1  todo  Set up cache infrastructure
```

Outcome: `kb-2` exists with status `open`. Two relations exist: `kb-2
related-to kb-0` (bidirectional) and `kb-2 depends-on kb-1` (unidirectional).

### Scenario 2: Create a note with a user-defined relation

Starting state: `kb-5` is a todo.

```
$ echo "After profiling, the bottleneck is in the serializer." \
    | bs add note "Serializer profiling results" --uni informs,kb-5
Created note: kb-6 (note_01def...)
  informs  kb-5  todo  Optimize serialization path
```

Outcome: `kb-6` exists with status `active`. One unidirectional relation
`kb-6 informs kb-5` exists.

### Scenario 3: Inline relation with invalid target

Starting state: `kb-3` exists, `kb-99` does not.

```
$ echo "Body" | bs add todo "Some task" --related-to kb-3 --depends-on kb-99
Error: Item not found: kb-99
```

Outcome: no todo is created. No relations are created.

### Scenario 4: Multi-relation relate

Starting state: `kb-0` is a note, `kb-1`, `kb-2`, `kb-3` are todos.

```
$ bs relate kb-0 --related-to kb-1 --related-to kb-2 --related-to kb-3
Related: kb-0 related-to kb-1 (bidirectional)
Related: kb-0 related-to kb-2 (bidirectional)
Related: kb-0 related-to kb-3 (bidirectional)
```

Outcome: three bidirectional `related-to` relations from `kb-0`.

### Scenario 5: Mixed relation kinds in one relate call

Starting state: `kb-5` is a todo, `kb-0` is a note, `kb-4` is a todo.

```
$ bs relate kb-5 --related-to kb-0 --depends-on kb-4
Related: kb-5 related-to kb-0 (bidirectional)
Related: kb-5 depends-on kb-4 (unidirectional)
```

### Scenario 6: Multi-relation relate with invalid target

Starting state: `kb-0` exists, `kb-1` exists, `kb-99` does not.

```
$ bs relate kb-0 --related-to kb-1 --depends-on kb-99
Error: Item not found: kb-99
```

Outcome: no relations are created (atomic failure).

### Scenario 7: JSON output for add with inline relations

```
$ echo "Body" | bs add todo "Task" --related-to kb-0 --json
```

The JSON response includes the created item and its relations.

## Constraints

1. **Existing CLI commands must continue to work.** `bs add todo "Title"`
   with no relation flags must behave exactly as it does today. `bs relate`
   with a single relation flag must create the relation and print the same
   human-readable output as today. The `--json` output format for `relate`
   changes to the envelope format (requirement 9); this is acceptable because
   there are no current callers.

2. **Relation semantics are unchanged.** Inline relations on `add` and
   multi-target `relate` create the same relation objects as today's
   single-relation `relate` command. No new relation kinds or
   directionality rules are introduced.

3. **No new runtime dependencies.**

4. **On-disk formats unchanged.** Neither the SQLite schema nor the JSONL
   format changes. Relations created inline are stored identically to
   relations created via `relate`.

## Open Questions

*None — all questions from the requirements and refinement steps are resolved.*

## Approaches

Both approaches share the same infrastructure changes:

- **`Kb_service.t` gains a `db` field.** `Relation_service`'s transaction
  helper (`Sqlite.with_transaction`) needs access to `Sqlite3.db`.
  `Kb_service.init` already receives a `Repository.Root.t`; adding
  `db = Repository.Root.db root` to the record is a one-line change.
  Tests that use `:memory:` databases are unaffected — `Root.db` works
  for both.

- **Both commands switch to `Arg.opt_all` for the four relation flags.**
  `cmd_add.ml` and `cmd_relate.ml` change `Arg.opt (some T) None` to
  `Arg.opt_all T []` for each of `--depends-on`, `--related-to`,
  `--uni`, and `--bi`. The `run` function receives four lists instead
  of four options, and validates that their combined length is ≥ 1 for
  `relate` (zero flags remains an error).

  *Flag-ordering caveat:* `opt_all` collects each flag type
  independently. The interleaved order across flag types
  (`--related-to kb-1 --depends-on kb-2 --related-to kb-3`) cannot be
  recovered from four separate lists; relations are created in
  type-grouped order (`related-to` entries first, then `depends-on`,
  etc.). Requirements 3 and 4 say "flag order" — this satisfies the
  spirit (deterministic, predictable order) but not the letter. The
  practical impact is zero because relation creation order has no
  semantic effect.

- **A shared `relate_spec` type** represents a single relation to
  create. Both commands parse their four flag lists into a
  `relate_spec list`:

  ```ocaml
  type relate_spec = {
    target        : string;
    kind          : string;
    bidirectional : bool;
  }
  ```

  The four lists are concatenated in the order
  `depends_on @ related_to @ uni @ bi` to form the spec list.

### Approach A: Enrich `Relation_service`, service layer carries metadata

**Mechanism**

Extend `Relation_service.relate_result` to carry the target's entity
type and title alongside the existing fields. This is the data
`cmd_add.ml` needs for the inline-relation display lines, and it is
available at zero extra cost inside `relate` — `Item_service.find`
already resolves the full `item` before creating the relation.

New `relate_result` in `Relation_service`:

```ocaml
type relate_result = {
  relation      : Data.Relation.t;
  source_niceid : Data.Identifier.t;
  target_niceid : Data.Identifier.t;
  target_type   : string;
  target_title  : Data.Title.t;
}
```

Add `relate_many` to `Relation_service`:

```ocaml
val relate_many :
  t ->
  source:string ->
  specs:relate_spec list ->
  (relate_result list, error) result
```

`relate_many` validates all specs first (resolves all targets,
validates all kind strings), then creates all relations in a loop. It
does **not** start a transaction — the caller provides the transaction
context. If validation fails on any spec, no relations are created (the
loop never runs). If a creation fails (e.g., duplicate), the caller's
transaction rolls back.

Internally `relate_many` re-uses the existing resolution and validation
logic from `relate`:

```ocaml
let relate_many t ~source ~specs =
  let open Result.Syntax in
  let* source_item = Item_service.find t.items ~identifier:source in
  let source_typeid = typeid_of_item source_item in
  let source_niceid = niceid_of_item source_item in
  (* Validate all specs before creating anything *)
  let* resolved = Data.Result.sequence (List.map (fun spec ->
    let* target_item = Item_service.find t.items ~identifier:spec.target in
    let* kind = Parse.relation_kind spec.kind in
    Ok (target_item, kind, spec.bidirectional)
  ) specs) in
  (* Create all relations *)
  Data.Result.sequence (List.map (fun (target_item, kind, bidirectional) ->
    let rel = Data.Relation.make
      ~source:source_typeid
      ~target:(typeid_of_item target_item)
      ~kind ~bidirectional in
    let+ relation =
      RelationRepo.create t.relation_repo rel
      |> Result.map_error map_relation_repo_error
    in
    { relation;
      source_niceid;
      target_niceid = niceid_of_item target_item;
      target_type   = entity_type_of_item target_item;
      target_title  = title_of_item target_item }
  ) resolved)
```

`Kb_service` adds `add_todo_with_relations` and
`add_note_with_relations`. Both wrap entity insert + `relate_many`
in a single `_with_flush` call and a `Sqlite.with_transaction`:

```ocaml
type add_with_relations_result = {
  niceid    : Data.Identifier.t;
  typeid    : Data.Uuid.Typeid.t;
  entity_type : string;
  relations : relation_entry list;  (* existing type from Query_service *)
}

let add_note_with_relations t ~title ~content ~specs =
  _with_flush t (fun () ->
    let open Result.Syntax in
    Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () ->
        let* note = Note.add t.notes ~title ~content
                    |> Result.map_error map_note_error in
        let source = Identifier.to_string (Data.Note.niceid note) in
        let* results = Relation.relate_many t.relation_svc ~source ~specs in
        let relations = List.map relation_entry_of_result results in
        Ok { niceid = Data.Note.niceid note;
             typeid = Data.Note.id note;
             entity_type = "note";
             relations }))
```

Where `relation_entry_of_result` converts `Relation_service.relate_result`
to the existing `relation_entry` type (same fields, direct mapping).

`Kb_service.relate` is updated to accept a list of specs and wraps
`Relation.relate_many` in a transaction:

```ocaml
val relate :
  t ->
  source:string ->
  specs:relate_spec list ->
  (relate_result list, error) result

let relate t ~source ~specs =
  _with_flush t (fun () ->
    Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () ->
        Relation.relate_many t.relation_svc ~source ~specs))
```

**What changes for consumers**

- `cmd_add.ml` calls `add_todo_with_relations` / `add_note_with_relations`
  with the parsed `relate_spec list`. When relations are present, it
  prints the "Created …" line followed by one `format_relation_entry`
  line per result. For `--json`, it includes a `relations` array.
- `cmd_relate.ml` calls the updated `relate` with a spec list. It
  prints one "Related: …" line per result. For `--json`, it emits the
  envelope `{"ok":true,"relations":[...]}`.
- The existing `add_note` and `add_todo` functions in `Kb_service`
  remain unchanged for callers that pass no relation specs.
- `relate_result` gains two new fields (`target_type`, `target_title`);
  all existing code that destructures it by field name continues to
  compile. `cmd_relate.ml` simply ignores the new fields.

**What changes for tests**

- Existing `add_*_expect.ml` tests: unchanged (no relation flags).
- Existing `relate_expect.ml` tests: the `--json` output format changes
  to the envelope (req 9); all 9 tests need their `[%expect]` blocks
  updated.
- New integration tests for `add` with relations: inline relation
  creation, invalid target, multiple relations, JSON output.
- New integration tests for multi-relation `relate`: repeated flags,
  mixed kinds, invalid target (atomic rollback), JSON envelope.
- `relation_service_expect.ml`: the existing `relate` tests continue
  to work; new tests for `relate_many` covering multi-spec and
  validation-first semantics.

**Limitations**

- Cross-flag ordering: relations are created in type-grouped order, not
  strict command-line flag order (see shared caveat above).
- `relate_many` validates specs left-to-right and fails fast on the
  first invalid spec. Error messages name only the first invalid target.
- The `relate_many` two-pass structure (validate-all, create-all) means
  a duplicate error is only detected during the create phase, not the
  validate phase. Duplicates are detected and rolled back by the
  transaction, but the error message refers to the duplicate constraint
  rather than the specific spec.

---

### Approach B: Minimal service changes, CLI uses `show` for display

**Mechanism**

The service layer is extended only to support atomicity and multi-spec
input, but does **not** return entity metadata for the created
relations. The CLI calls `Kb_service.show` on the newly created entity
to obtain display data.

`Relation_service` is **unchanged**. `Kb_service` gains:

```ocaml
(* add returns the entity; relations are not in the result *)
val add_note_with_relations :
  t ->
  title:Data.Title.t ->
  content:Data.Content.t ->
  specs:relate_spec list ->
  (Data.Note.t, error) result

(* relate returns minimal results *)
val relate :
  t ->
  source:string ->
  specs:relate_spec list ->
  (relate_result list, error) result
```

`add_note_with_relations` internally calls `Relation_service.relate`
in a loop inside a transaction:

```ocaml
let add_note_with_relations t ~title ~content ~specs =
  _with_flush t (fun () ->
    let open Result.Syntax in
    Sqlite.with_transaction t.db
      ~on_begin_error:(fun msg -> Repository_error msg)
      (fun () ->
        let* note = Note.add t.notes ~title ~content
                    |> Result.map_error map_note_error in
        let source = Identifier.to_string (Data.Note.niceid note) in
        let* _ = Data.Result.sequence (List.map (fun spec ->
          Relation.relate t.relation_svc
            ~source ~target:spec.target
            ~kind:spec.kind ~bidirectional:spec.bidirectional
        ) specs) in
        Ok note))
```

In `cmd_add.ml`, when `specs` is non-empty, the CLI calls
`Kb_service.show` after `add_note_with_relations` succeeds to obtain
the `show_result` with outgoing relations:

```ocaml
let run_note title specs json =
  ...
  match Service.add_note_with_relations ... ~specs with
  | Ok note ->
      let niceid = Identifier.to_string (Note.niceid note) in
      let typeid  = Typeid.to_string (Note.id note) in
      Printf.printf "Created note: %s (%s)\n" niceid typeid;
      if specs <> [] then begin
        let show = Service.show ctx_service ~identifier:niceid in
        (* print outgoing relations from show_result *)
        ...
      end
  ...
```

For `relate --json`, the existing `relate_result` type is reused; the
CLI constructs the envelope from the list.

**What changes for consumers**

Same CLI flag changes as Approach A. The `add` output is identical to
Approach A. The `relate` output is identical to Approach A.

**What changes for tests**

Largely the same as Approach A for integration tests. The key difference
is that `Relation_service` has no new functions to unit-test.

**Limitations**

- **One extra DB query per `add` with relations.** `show` performs two
  `find_by_source`/`find_by_target` queries plus one item lookup per
  relation. For a newly created entity with N relations, this is N+2
  additional queries. For a knowledge base of typical size (hundreds of
  items), these are all keyed lookups — fast, but not free.
- **`Relation_service.relate` is called once per spec** in a loop.
  Each call performs an independent `Item_service.find` for source and
  target. For an `add` with N inline relations, the source is looked up
  N times (once per `relate` call). Approach A validates and resolves
  each target once and skips the source re-lookup.
- **`show` returns all relations, not just inline ones.** For a newly
  created entity this is fine — there are no prior relations. But if
  `add_with_relations` is later extended to support creating entities
  that already have relations (e.g., batch import), the `show`-based
  display would include unexpected relations. This is a future concern,
  not a current one.
- **`Data.Result.sequence` stops on first error.** If spec 1 is valid
  but spec 2 references a nonexistent target, spec 1's relation is
  created inside the transaction before spec 2 fails. The transaction
  rolls back correctly, but the error path does not validate all specs
  upfront.

---

## Design Decisions

### 1. `Arg.opt_all` for multi-value flags (both approaches)

`opt_all` is the only cmdliner mechanism that collects repeated
occurrences of a flag into a list while preserving per-flag ordering.
The comma-separated alternative (`--related-to kb-1,kb-2`) is blocked
by the existing use of comma as the KIND,TARGET separator in `--uni`
and `--bi`. Repeated flags are also the conventional CLI pattern for
multi-value options (e.g., `curl -H`).

### 2. Transaction scope in `Kb_service` (both approaches)

`_with_flush` is the natural point for transaction wrapping — it
already delineates the scope of a logical mutation. `Sqlite.with_transaction`
wraps the inner callback; `_with_flush` wraps the transaction. The
sub-services (Note, Todo, Relation) remain transaction-naive. This
keeps transaction management in one place and avoids the nested-transaction
problem that would arise if each sub-service started its own transaction.

Placing `Sqlite.with_transaction` in the service layer rather than the
repository layer is appropriate here because the transactions in question
span multiple repositories. "Create a note and its relations" touches
`Repository.Note` and `Repository.Relation`; neither repository can
manage a transaction that covers the other without introducing a
cross-repository dependency. The service layer is the only layer that
coordinates across repositories, so it is the natural home for
multi-repository transaction boundaries.

The codebase was designed with this in mind: `Repository.Sqlite.with_transaction`
takes `Sqlite3.db` as a parameter rather than managing the connection
internally, and `Repository.Root.db` is a public accessor. If
transactions were purely a repository concern, neither would need to be
exposed. Adding `db` to `Kb_service.t` is consistent with this design.

The Unit of Work pattern — a transaction-context object threaded through
the call stack — is the usual alternative. It gives a cleaner abstraction
boundary if repositories might someday back onto different storage
engines. Here, all repositories are explicitly SQLite and `Root.db` is
already part of the public API; that abstraction does not exist to
protect. Direct use of `Sqlite.with_transaction` in `Kb_service` is
proportionate to the codebase's scale and existing conventions.

### 3. `relate_many` validate-then-create (Approach A only)

`relate_many` resolves all targets and validates all kind strings before
calling `Repository.Relation.create` for any of them. This means
validation errors (item not found, invalid kind) are reported without
side-effects. Duplicate errors can only be detected at create time
(after the first pass), but the transaction ensures rollback.

Alternative: validate-and-create each spec in sequence (fail immediately
on any error). This is simpler but can leave the transaction partially
written when the transaction hasn't committed. With `Sqlite.with_transaction`,
rollback handles this correctly either way. The validate-first approach
is chosen for clarity: it separates concerns (validation vs. persistence)
and makes the two-phase structure explicit.

---

## Rejected Alternatives

**CLI-side resolution (no service changes for display metadata):**
The CLI calls `show` after every `add` to get relation entries, without
changing `add_note`/`add_todo` return types. Rejected because
`Relation_service.relate` is still called once per spec in a loop, with
the source re-resolved each time, and there is no transaction boundary
spanning the entity insert and the relation inserts. Requirement 7
(atomicity) cannot be satisfied without service layer changes.

**Comma-separated multi-target syntax** (`--related-to kb-1,kb-2`):
Blocked by the existing `--uni KIND,TARGET` and `--bi KIND,TARGET`
parsing, which already uses comma as the separator between the kind and
the target. A custom two-separator design (e.g., semicolons for targets)
would be inconsistent with the existing flag conventions.

---

## Consequences and Trade-offs

| Dimension | Approach A | Approach B |
|---|---|---|
| Extra DB queries per `add` with relations | None | 1 `show` per invocation |
| Extra DB queries per relation spec | None (source resolved once) | 1 source lookup per spec |
| New types in `Relation_service` | `relate_many`, enriched `relate_result` | None |
| `cmd_add.ml` complexity | Formats results directly | Calls `show`, delegates to `format_relation_entry` |
| Service-level unit testability | Full: `relate_many` tested directly | Partial: output path only via integration tests |
| `show` code reuse | No (formats inline) | Yes (reuses `format_relation_entry`) |
| Redundant `Item_service.find` calls | None (source resolved once in `relate_many`) | N (once per `relate` call in loop) |
| Lines changed in `lib/service/` | ~60 (new types + `relate_many`) | ~20 (new add functions only) |

---

## Requirement Coverage

*For the recommended Approach A.*

| Req | How satisfied |
|---|---|
| 1. Inline relations on `add` | `add_todo/note_with_relations` in `Kb_service` |
| 2. All relation kinds inline | `relate_spec` carries kind + bidirectional; all four flags (`--depends-on`, `--related-to`, `--uni`, `--bi`) as `opt_all` |
| 3. Multiple relations per `add` | `relate_many` takes a list; `Kb_service` passes the merged spec list |
| 4. Multiple relations per `relate` | Updated `Kb_service.relate` takes a spec list |
| 5. Human-readable add output | `add_with_relations_result.relations` (type `relation_entry list`) fed to `format_relation_entry` in `cmd_add.ml` |
| 6. JSON add output | `relations` array in `add --json`; each element from `relation_entry_to_json` (reused from `cmd_show.ml`) |
| 7. `add` atomicity | `Sqlite.with_transaction` wraps entity insert + `relate_many` in `Kb_service` |
| 8. `relate` atomicity | `Sqlite.with_transaction` wraps `relate_many` in `Kb_service.relate` |
| 9. `relate --json` envelope | `cmd_relate.ml` wraps results in `{"ok":true,"relations":[...]}` |

---

## Recommendation

**Approach A.**

The core advantage over Approach B is that `Relation_service.relate_many`
resolves each target exactly once and returns the metadata at no
additional cost. Approach B pays for a post-creation `show` query and
re-resolves the source on every spec. For a 10-relation `add` command,
Approach B does approximately 22 extra queries (10 source lookups + 10
target-metadata lookups via `show`'s per-relation item resolution + 2
show queries) versus 0 for Approach A.

The service-level unit tests for `relate_many` are also valuable: they
test the validate-first semantics, the mixed-kind behavior, and the
atomic rollback without standing up the full binary, which is faster and
more precise than integration tests.

The cost is ~40 additional lines in `lib/service/relation_service.ml`
and a new result type in `kb_service.mli`. These are straightforward
additions; the pattern (validate-then-create, service-layer error
types) is already established in the codebase.

Approach B remains a viable fallback if the `relate_many` addition is
rejected — it can be implemented entirely within `Kb_service` without
touching `Relation_service`.
