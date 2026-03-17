# Design: Performance Test Suite

## Problem Statement

`bs` flushes the entire knowledge base from SQLite to JSONL on every
write operation (`add`, `update`, `resolve`, `archive`, `relate`). The
flush queries all todos, notes, and relations, serializes them to JSON,
computes an MD5 hash, and writes the result atomically via a temp file
and `Unix.rename`. Rebuild performs the inverse: it deletes all SQLite
rows and re-inserts everything from the JSONL file.

These operations are O(n) in the total number of entities. For a
knowledge base with a handful of items this is invisible, but there is
no evidence that it remains acceptable at hundreds or thousands of
items. The project also has no performance test infrastructure — there
is no way to measure, track, or reason about how operations scale.

This design adds a performance test suite that measures single-operation
latency and multi-operation throughput at varying database sizes (up to
10,000 items), and rebuild time at scale. The suite runs separately from
`dune runtest` and reports timing data for human review.

## Background

### Flush: SQLite → JSONL

Every write operation flows through `Kb_service._with_flush`
(`lib/service/kb_service.ml:82–93`), which wraps the actual write in a
mark-dirty / flush bracket:

```ocaml
let _with_flush t f =
  let open Result.Syntax in
  let* () = match t.sync with
    | None -> Ok ()
    | Some sync -> Sync_service.mark_dirty sync |> Result.map_error map_sync_error
  in
  let* result = f () in
  let* () = match t.sync with
    | None -> Ok ()
    | Some sync -> Sync_service.flush sync |> Result.map_error map_sync_error
  in
  Ok result
```

Six operations use this wrapper: `add_note`, `add_todo`, `update`,
`resolve`, `archive`, `relate`. Two operations bypass it: `list` and
`show` (read-only, no flush).

`Sync_service.flush` (`lib/service/sync_service.ml:63–82`) does the
following when the dirty flag is set:

1. `Repository.Todo.list_all` — `SELECT id, niceid, title, content,
   status FROM todo ORDER BY id` (full table scan).
2. `Repository.Note.list_all` — same pattern against the `note` table.
3. `Repository.Relation.list_all` — `SELECT source, target, kind,
   bidirectional FROM relation ORDER BY source, target, kind`.
4. `Config.get "namespace"` — single row lookup.
5. `Jsonl.write` — serializes, hashes, and atomically writes the JSONL
   file (described below).
6. Stores the returned content hash in the config table and clears the
   dirty flag.

When the dirty flag is *not* set, `flush` returns `Ok ()` immediately
without touching the database or filesystem.

### JSONL serialization

`Jsonl.write` (`lib/repository/jsonl.ml:68–95`) builds the file
in-memory and writes it atomically:

1. Creates `(sort_key, json)` pairs for every entity. Sort keys are the
   TypeId string for todos and notes, and
   `"relation:<source>:<target>:<kind>"` for relations.
2. Sorts all pairs by key (`List.sort` with `String.compare`).
3. Serializes each JSON value with `Yojson.Safe.to_string` and
   concatenates all lines with `"\n"`.
4. Computes the MD5 hash of the concatenated entity content:
   `Digest.string entity_content |> Digest.to_hex`.
5. Prepends a header line containing the version (`"1"`), namespace,
   entity count, and content hash.
6. Writes to `<path>.tmp` and atomically renames to `<path>`.

The entire file is rebuilt from scratch on every flush — there is no
incremental update. At 10,000 entities this means 10,000
`Yojson.Safe.to_string` calls, one `List.sort` over 10,000 elements, a
single string concatenation, one MD5 digest, and one file write.

### Rebuild: JSONL → SQLite

`Sync_service.force_rebuild` (`lib/service/sync_service.ml:93–129`):

1. `Jsonl.read` — reads the entire JSONL file into memory, parses each
   line with `Yojson.Safe.from_string`, and validates every field.
2. Sorts parsed records by the same key scheme used during flush.
3. Deletes all rows from four tables in sequence: `todo`, `note`,
   `relation`, `niceid` (each via `DELETE FROM <table>`).
4. Re-inserts every entity: `Repository.Todo.import` and
   `Repository.Note.import` for data entities,
   `Repository.Relation.create` for relations. Each `import` call also
   allocates a fresh niceid via `Niceid.allocate`, which runs a
   `SELECT IFNULL(MAX(niceid), -1)` and an `INSERT` inside a
   transaction (`lib/repository/niceid.ml:40–60`).
5. Stores the content hash from the JSONL header and clears the dirty
   flag.

At 10,000 entities, rebuild performs 10,000 JSON parses, 40,000+
individual SQL statements (delete-all on 4 tables, then per-entity
insert + niceid allocate), and 10,000 niceid transactions.

### Startup sync

Every CLI invocation that opens an existing knowledge base calls
`Sync_service.rebuild_if_needed`
(`lib/service/sync_service.ml:131–145`) during `Kb_service.open_kb`.
This reads only the JSONL header (one `input_line` via
`Jsonl.read_header`) and compares its content hash against the stored
hash in the config table. If the hashes match and the dirty flag is not
set, no further I/O occurs. If the JSONL file has changed externally
(hash mismatch) or no stored hash exists, a full `force_rebuild` runs.
If the dirty flag is set but hashes match, it flushes instead.

In practice, for repeated CLI invocations during a session (the
steady-state case the benchmarks target), `rebuild_if_needed` amounts
to one file open, one line read, one config lookup, and one string
comparison — essentially free.

### Dirty flag

The dirty flag is a key-value pair in the SQLite `config` table
(`key = "dirty"`, `value = "true" | "false"`). `mark_dirty` sets it
before the write; `flush` clears it after successfully writing the
JSONL file. There is no code path in normal operation that leaves the
dirty flag set after a command completes — `_with_flush` always calls
`flush` after the write succeeds.

The explicit `bs flush` command
(`lib/service/kb_service.ml:146–152`) unconditionally calls
`mark_dirty` before `flush`, forcing a re-serialize even if nothing
changed. This is the only way to trigger a flush without a preceding
write.

### Schema and data model

The SQLite database has five tables:

| Table      | Primary key                | Rows per entity |
|------------|----------------------------|-----------------|
| `todo`     | `id TEXT`                  | 1               |
| `note`     | `id TEXT`                  | 1               |
| `relation` | `(source, target, kind)`   | 1               |
| `niceid`   | `typeid TEXT`              | 1 per todo/note |
| `config`   | `key TEXT`                 | 3 (namespace, dirty, content_hash) |

Todos and notes share an identical column layout: `id`, `niceid`
(UNIQUE), `title`, `content`, `status`. Both use text-based TypeIds as
primary keys and text niceids with a unique constraint. Neither table
has indices beyond the primary key and the unique constraint on
`niceid`.

Relations store TypeIds as plain text with a composite primary key.
There are no foreign keys between the relation table and the todo/note
tables, and no indices on `source` or `target` individually — the
`find_by_source` and `find_by_target` queries
(`lib/repository/relation.ml:93–109`) rely on the composite primary
key index for source lookups and perform a full scan for target
lookups.

### `create` vs. `import`

Both `Repository.Todo` and `Repository.Note` expose two insertion
paths:

- `create` (`lib/repository/todo.ml:80–81`) — generates a fresh
  TypeId via `Data.Todo.make_id ()`, allocates a niceid, inserts.
  Used during normal `bs add` operations.
- `import` (`lib/repository/todo.ml:83–84`) — accepts a caller-
  provided TypeId, allocates a niceid, inserts. Used during rebuild to
  preserve TypeIds from the JSONL file.

Both delegate to a shared `_insert` helper that allocates the niceid
and runs the SQL INSERT. The niceid allocation
(`Niceid.allocate`) always queries `MAX(niceid)` in a transaction,
regardless of whether a sequential allocation would be safe — there is
no bulk-insert optimisation.

### CLI binary structure

The `bs` binary (`bin/main.ml`, 43 lines) is a Cmdliner command group
with 12 subcommands. Each command file follows a uniform pattern:
create an `App_context`, call a `Kb_service` function, handle the
result, clean up. The binary compiles to
`_build/default/bin/main.exe`.

Every invocation opens the SQLite database, initialises all five
repository handles via `Root.init`, and runs `rebuild_if_needed` —
even for read-only commands. This is the fixed per-invocation overhead
that subprocess-based benchmarks will include.

### Existing test infrastructure

The project has two test suites:

**Unit tests** (`test/`, 34 `.ml`/`.mli` files, ~3,500 lines) use
`ppx_expect` inline tests, organised in subdirectories mirroring
`lib/` (`test/data/`, `test/repository/`, `test/service/`,
`test/control/`). They run via `dune runtest`.

**Integration tests** (`test-integration/`, 14 `.ml` files, ~1,900
lines) invoke the `bs` binary as a subprocess and assert on exit
codes, stdout, and stderr. Key infrastructure in `test_helper.ml`
(167 lines):

- `run_bs ~dir ?stdin args` — runs `bs` via `Sys.command` with
  `TERM=dumb`, captures stdout/stderr to temp files, returns
  `{ exit_code; stdout; stderr }`.
- `with_git_root f` — creates a temp directory with `.git/`, cleans
  up after `f` completes.
- `init_kb dir` — calls `bs init -d <dir> -n kb` as a subprocess.
- `normalize_dir`, `normalize_typeids` — replace non-deterministic
  values with placeholders for expect-test matching.

The binary path is resolved lazily:
`<project_root>/_build/default/bin/main.exe`.

Integration tests use `(deps %{bin:bs} (universe))` in their dune
file, which ensures the binary is built before tests run and disables
incremental caching (tests always re-run).

**Dune aliases:**

| Alias       | Purpose                               |
|-------------|---------------------------------------|
| `@runtest`  | All unit + integration expect tests   |
| `@runcheck` | Static checks (find-unused)           |

There is no `@runperf` alias or any performance testing infrastructure.

### JSONL file construction

The JSONL format is a header line followed by one JSON object per
entity. Each line is self-contained — no niceids (those are a runtime
concern), no cross-references beyond TypeIds in relation records. A
valid JSONL file can be constructed by:

1. Writing a header line:
   `{"_kbases":"1","namespace":"<ns>","entity_count":<n>,"content_hash":"<md5>"}`.
2. Writing one line per entity, sorted by TypeId (or `relation:` sort
   key).
3. Computing `content_hash` as `Digest.to_hex (Digest.string
   <all-entity-lines-joined-by-newline>)`.

The format uses `Yojson.Safe` for both serialization and parsing. The
parsing path (`Jsonl.read`, `lib/repository/jsonl.ml:216–225`)
validates every field — TypeIds via `Data.Uuid.Typeid.parse`, titles
via `Data.Title.make`, content via `Data.Content.make`, statuses via
`status_of_string`. This means synthetic JSONL data must pass the same
validation constraints as data created through the CLI: titles 1–100
characters, content 1–10,000 characters, valid TypeId prefixes
(`todo_`, `note_`), valid relation kind format.

### Observations

1. **Direct JSONL construction is straightforward.** The JSONL format
   is fully specified by `lib/repository/jsonl.ml` and uses standard
   JSON. A benchmark harness can generate synthetic JSONL files
   without calling `bs` — it needs to produce valid TypeIds, titles
   (≤100 chars), content (≤10,000 chars), relation kinds (lowercase
   alphanumeric + hyphens), and a correct MD5 content hash. The
   `Jsonl.read` parser will validate everything during rebuild,
   catching malformed synthetic data early. This directly addresses
   open question 2: constructing JSONL files programmatically and
   running `bs rebuild` is a viable fast-setup strategy for
   populating large databases.

2. **Flush isolation is not achievable through normal CLI paths.** The
   `_with_flush` wrapper couples every write to an immediate flush —
   there is no CLI command that writes to SQLite without flushing
   afterward. The explicit `bs flush` command calls `mark_dirty`
   first, then `flush`, but the resulting flush re-serializes all
   entities regardless of whether anything actually changed. Running
   `bs flush` on an already-clean database exercises the "dirty flag
   not set → skip" path (`sync_service.ml:65–66`), not the
   serialization path. To measure flush cost in isolation, the
   benchmark would need to either: (a) manipulate the config table
   directly to set `dirty = "true"` without performing a write, or
   (b) accept that flush cost is always measured as part of a write
   operation. This addresses open question 3.

3. **Niceid allocation is per-entity during rebuild.** Each entity
   imported during `force_rebuild` triggers an individual
   `Niceid.allocate` call, which runs `SELECT IFNULL(MAX(niceid), -1)`
   inside a transaction. At 10,000 entities, this means 10,000
   sequential max-queries against a growing `niceid` table. There is
   no bulk allocation path. This could be a significant component of
   rebuild time.

4. **No indices on relation source/target.** `find_by_target` queries
   the relation table with `WHERE target = ?` but the only index is
   the composite primary key `(source, target, kind)`. For
   `find_by_source` the primary key prefix is useful; for
   `find_by_target` SQLite must scan. This affects `bs show` latency
   when displaying incoming relations, though `show` does not trigger
   flush and is a read-only path. At 10,000 relations this scan may
   or may not be measurable.

5. **Rebuild deletes before inserting.** `force_rebuild` issues four
   `DELETE FROM` statements (one per table) before re-inserting. These
   are not wrapped in a single transaction — each delete and each
   import call is its own implicit or explicit transaction. At scale
   this means many individual SQLite transactions rather than one
   batch operation.

6. **`bs flush` forces a re-serialize.** The explicit `bs flush`
   command (`kb_service.ml:146–152`) calls `mark_dirty` before
   calling `Sync_service.flush`. This means `bs flush` always
   re-serializes even if the JSONL file is already current. Benchmark
   scenario 6 can use this: run `bs flush` and the first invocation
   will force-serialize (because `mark_dirty` was called), giving a
   measurement of full flush cost without needing to manipulate the
   config table directly.

7. **Per-invocation fixed cost.** Every `bs` command pays startup
   overhead: process spawn, Cmdliner argument parsing,
   `Sqlite3.db_open`, five `CREATE TABLE IF NOT EXISTS` statements,
   three config lookups (namespace, dirty, content_hash), one JSONL
   header read + hash comparison. This overhead is constant regardless
   of database size and sets the floor for single-operation latency.

8. **The test helper's `run_bs` uses `Sys.command`.** The integration
   test runner invokes `bs` via a shell command string
   (`test_helper.ml:89–99`), which means each invocation spawns a
   shell process in addition to the `bs` process. A performance
   benchmark using the same pattern will include shell overhead in its
   timing. An alternative is `Unix.create_process`, which spawns
   directly without a shell.

## Requirements

1. **Single-operation latency at scale.** Measure wall-clock time of
   individual CLI operations against knowledge bases pre-populated
   with 100, 1,000, and 10,000 items. Write operations (`add todo`)
   are measured at all three tiers — each triggers a full flush, so
   latency scales with database size. Read operations (`list todo`,
   `show`) are measured at 10,000 items only — they bypass flush,
   making scaling less of a concern; a single large-tier measurement
   is sufficient to confirm they remain fast. The `show` test targets
   an entity that is the target of at least one relation, exercising
   the `find_by_target` query path which lacks a covering index and
   scans the relation table (observation 4). Each operation is timed
   independently so that the cost of flush-on-write is visible as the
   database grows. For write-operation samples, the database and JSONL
   file are restored to the pre-populated baseline between iterations
   to ensure sample independence — without reset, the 100-item tier
   would grow by 5% over 5 samples, and the JSONL file would drift
   from the original.

   `resolve` is not measured separately; it uses the same `_with_flush`
   wrapper as `add` and will exhibit the same scaling behavior.
   `flush` is covered by scenario 6.

   *Rationale:* The flush-on-every-write design serializes all entities
   on each write. If latency degrades noticeably at 1K–10K items, we
   need to know before users hit it. Refined after codebase analysis
   showed all write operations share the `_with_flush` wrapper
   (`kb_service.ml:82–93`), making `add todo` representative.

2. **Sequential throughput.** Measure the time to perform N sequential
   write operations (e.g., 50 `add todo` commands in a loop) against
   databases of varying sizes (empty, 1,000, 10,000 items). The
   database is restored to its initial state between samples so each
   sample measures identical workload against the same starting point.
   This simulates an agent adding a batch of todos in quick succession.

   *Rationale:* A coding agent might create many items in a short
   burst. Per-operation overhead compounds; this test reveals the
   aggregate cost. State reset between samples added to ensure sample
   independence — without reset, successive samples operate on a
   growing database.

3. **Rebuild time at scale.** Measure the time to rebuild a SQLite
   database from a JSONL file containing 100, 1,000, and 10,000
   entities. This simulates `bs rebuild` after a fresh clone or a
   merge that brought in many new items.

   *Rationale:* Rebuild is triggered after clone and merge — both
   moments where the user is waiting. Slow rebuild directly affects
   perceived responsiveness.

4. **Report, don't assert.** Tests print timing results in a
   human-readable format (operation, item count, elapsed time). No
   threshold-based pass/fail assertions. The goal is to establish a
   baseline and understand the current state.

   *Rationale:* Thresholds are meaningless without a baseline and are
   brittle across machines. We will add pass/fail criteria after
   reviewing initial results.

5. **Separate from `runtest`.** Performance tests run under a
   dedicated dune alias (e.g., `dune build @runperf`) or as a
   standalone executable, not as part of `dune runtest`. They must not
   slow down the normal test cycle.

   *Rationale:* Performance tests are expensive to run and produce
   results that require human analysis, not automated pass/fail
   judgment.

6. **Deterministic setup via JSONL construction.** Each benchmark
   populates its database by constructing a synthetic JSONL file
   programmatically and running `bs rebuild` to build the SQLite
   database. This avoids the O(n²) cost of populating via sequential
   `bs add` calls (each of which triggers a full flush of all
   entities). Synthetic data must satisfy the validation constraints
   enforced by `Jsonl.read`: valid TypeId prefixes (`todo_`, `note_`),
   titles 1–100 characters, content 1–10,000 characters, lowercase
   alphanumeric-plus-hyphen relation kinds, and a correct MD5 content
   hash. Setup time (JSONL generation + rebuild) is measured separately
   and excluded from the reported operation timings.

   *Rationale:* Reproducibility. Tests should not depend on external
   state or prior runs. JSONL construction is viable because the format
   is fully specified in `lib/repository/jsonl.ml` and uses standard
   JSON. Refined after codebase analysis confirmed direct JSONL
   construction is straightforward (observation 1).

7. **CLI-only measurement via direct process creation.** All benchmarks
   invoke the `bs` binary as a subprocess, exactly as a user or agent
   would. No library-level benchmarks. The benchmark harness uses
   `Unix.create_process` rather than `Sys.command` to avoid including
   shell-spawning overhead in timing measurements. Subprocess overhead
   (process spawn, argument parsing, DB open, `rebuild_if_needed` hash
   check) is part of the real-world cost and is included in the
   numbers.

   *Rationale:* The target audience is CLI users and agents. Nobody
   embeds the library directly. Measuring the CLI path gives numbers
   that correspond to actual user experience. `Unix.create_process`
   eliminates the shell intermediary that `Sys.command` introduces,
   reducing measurement noise without changing what is measured.
   Refined after codebase analysis showed the integration test helper
   uses `Sys.command` (observation 8).

8. **Heterogeneous entity mix.** Benchmarks at each scale tier use a
   mix of todos, notes, and relations — not just todos. The default
   mix allocates items roughly equally between todos and notes, with
   relations comprising approximately 20% of the total entity count
   (e.g., 4,000 todos, 4,000 notes, 2,000 relations for a
   10,000-item database). The mix exercises different serialization
   paths in flush and different table scans in rebuild. A secondary
   homogeneous-todos benchmark at 10K provides a comparison point to
   see whether entity diversity affects performance.

   *Rationale:* Real knowledge bases contain all three entity types.
   A todos-only benchmark could miss costs in note or relation
   serialization. Comparing homogeneous vs. heterogeneous at the same
   scale reveals whether the mix matters.

9. **Multiple samples with summary statistics.** Each benchmark runs
   multiple iterations (after warm-up) and reports median, min, max,
   and standard deviation. The number of iterations should be
   configurable but default to something reasonable (e.g., 5–10 for
   expensive benchmarks, more for cheap ones).

   *Rationale:* A single measurement is noisy. Summary statistics
   reveal whether variance is high (suggesting external factors) or
   low (suggesting stable, trustworthy numbers).

10. **Warm-up run.** Each benchmark performs one discarded warm-up
    invocation before the timed samples. This primes the OS filesystem
    cache and SQLite page cache so that timed runs reflect
    steady-state performance.

    *Rationale:* In real-world use, `bs` is invoked repeatedly during
    a session — the filesystem cache is typically warm. Cold-start
    measurements would be dominated by OS-level cache misses that
    aren't representative of interactive use. A single discarded
    invocation is cheap and reduces noise without hiding real costs.

## Scenarios

### Scenario 1: Single add latency at scale

**Setup:** Knowledge bases pre-populated with a heterogeneous mix
(todos, notes, relations) at 100, 1,000, and 10,000 items.

**Action:** One `bs add todo` against each database, repeated for
multiple samples. Between samples, the database and JSONL file are
restored to the pre-populated baseline so each sample operates on an
identical starting state.

**Expected output:**
```
--- single-add-todo (5 samples, 1 warm-up) ---
  100 items    median  8.2ms   min  7.9ms   max  9.1ms   stddev  0.5ms
 1000 items    median 14.5ms   min 13.8ms   max 16.2ms   stddev  0.9ms
10000 items    median 42.3ms   min 40.1ms   max 47.8ms   stddev  2.9ms
```

Each row is a separate pre-populated database. Setup time is excluded.

### Scenario 2: Sequential add throughput on an empty database

**Setup:** An empty, initialized knowledge base.

**Action:** Add 50 todos in sequence via the CLI, repeated for
multiple samples. The knowledge base is re-initialized between
samples.

**Expected output:**
```
--- add-todo-burst (5 samples, 1 warm-up) ---
0 initial items   50 ops   median 2340ms total   46.8ms/op
```

### Scenario 3: Sequential add throughput on a large database

**Setup:** A knowledge base pre-populated with 10,000 mixed items.

**Action:** Add 50 todos in sequence via the CLI, repeated for
multiple samples. The knowledge base is restored to its 10,000-item
baseline between samples (re-initialized from JSONL).

**Expected output:**
```
--- add-todo-burst (5 samples, 1 warm-up) ---
10000 initial items   50 ops   median 4120ms total   82.4ms/op
```

Comparing scenarios 2 and 3 reveals how per-operation cost scales with
database size.

### Scenario 4: Rebuild at scale

**Setup:** `.kbases.jsonl` files containing a heterogeneous mix of
entities at 100, 1,000, and 10,000 items. No SQLite database present.

**Action:** `bs rebuild`, repeated for multiple samples. Between
samples, the SQLite database is deleted and a fresh empty database is
initialized so each rebuild starts from the same state.

**Expected output:**
```
--- rebuild (5 samples, 1 warm-up) ---
  100 items    median  120ms   min  115ms   max  135ms   stddev  7ms
 1000 items    median  480ms   min  460ms   max  520ms   stddev 22ms
10000 items    median 1830ms   min 1780ms   max 1950ms   stddev 65ms
```

### Scenario 5: Read operation latency at scale

**Setup:** A knowledge base with 10,000 mixed items.

**Action:** `bs list todo` and `bs show <niceid>`, repeated for
multiple samples. The shown entity is the target of at least one
relation, so the command exercises the `find_by_target` query path
(which scans the relation table due to the lack of an individual
index on the `target` column).

**Expected output:**
```
--- read-ops (5 samples, 1 warm-up) ---
list-todo   10000 items    median 85.2ms   min 82.1ms   max 90.3ms
show        10000 items    median  1.3ms   min  1.1ms   max  1.8ms
```

Read operations do not trigger flush, so these isolate query
performance from serialization cost.

### Scenario 6: Flush cost in isolation

**Setup:** A knowledge base with 10,000 mixed items.

**Action:** `bs flush`, repeated for multiple samples. `bs flush`
calls `mark_dirty` before flushing (`kb_service.ml:146–152`), forcing
a full re-serialize regardless of database state — no manual
manipulation of the dirty flag is needed.

**Expected output:**
```
--- flush (5 samples, 1 warm-up) ---
10000 items    median 38.7ms   min 36.2ms   max 42.1ms   stddev 2.3ms
```

This isolates the cost of the SQLite → JSONL serialization from the
cost of the write operation that would normally trigger it.

### Scenario 7: Homogeneous vs. heterogeneous comparison

**Setup:** Two 10,000-item databases — one containing only todos, the
other a mix of todos, notes, and relations.

**Action:** `bs flush` and `bs rebuild` on each, repeated for multiple
samples.

**Expected output:**
```
--- entity-mix-comparison (5 samples, 1 warm-up) ---
flush    10000 todos-only     median 35.1ms
flush    10000 mixed          median 38.7ms
rebuild  10000 todos-only     median 1720ms
rebuild  10000 mixed          median 1830ms
```

Reveals whether entity diversity has a meaningful impact on
flush/rebuild cost, or whether total item count is the dominant factor.

## Constraints

- **No changes to `bs` source code.** The performance tests observe
  existing behavior; they do not modify the application to accommodate
  measurement.
- **No new runtime dependencies.** The test suite uses only OCaml
  standard library, Unix, and existing project dependencies. Timing
  uses `Unix.gettimeofday` or `clock_gettime`.
- **Existing tests continue to pass.** Adding the performance test
  directory and dune rules must not affect `dune runtest` or
  `dune build @runcheck`.
- **Temporary directories.** Each benchmark creates and destroys its
  own temporary directory (with a git repo inside), following the
  pattern established by `test-integration/`.

## Resolved Decisions

1. **CLI-only.** No library-level benchmarks. Subprocess overhead is
   part of the real-world cost. (Resolved: requirement 7.)

2. **Heterogeneous mix with homogeneous comparison.** Default
   databases use a mix of todos, notes, and relations. A secondary
   homogeneous benchmark at 10K compares the two. (Resolved:
   requirement 8, scenario 7.)

3. **Warm-up included.** One discarded warm-up invocation per
   benchmark. Real-world use involves repeated invocations with a warm
   filesystem cache; cold-start noise is not representative.
   (Resolved: requirement 10.)

4. **Multiple samples.** Each benchmark runs multiple iterations and
   reports median, min, max, stddev. (Resolved: requirement 9.)

5. **JSONL construction for setup.** Pre-populate benchmark databases
   by constructing synthetic JSONL files programmatically and running
   `bs rebuild`, rather than sequential `bs add` calls. The JSONL
   format is fully specified and construction is straightforward.
   (Resolved: formerly open question 2; confirmed by observation 1.)

6. **`bs flush` for flush isolation.** Scenario 6 uses `bs flush` to
   measure flush cost. `bs flush` unconditionally calls `mark_dirty`
   before flushing (`kb_service.ml:146–152`), forcing a full
   re-serialize. No direct manipulation of the config table is needed.
   (Resolved: formerly open question 3; confirmed by observation 6.)

7. **Default sample count of 5.** Start with 5 samples per benchmark.
   The number is configurable; adjust based on observed variance in
   initial results. (Resolved: formerly open question 1.)

## Open Questions

None. All questions from the first pass have been resolved (see
Resolved Decisions 5–7).

## Approaches

Both approaches produce the same benchmark executable with the same
scenarios, timing, and reporting. They differ in how synthetic JSONL
files are generated for benchmark setup — the choice that determines
the executable's dependency footprint and its coupling to the code
under test. Shared infrastructure (subprocess invocation, timing,
state reset, statistics) is described fully in Approach A; Approach B
describes only what differs.

### Approach A: Library-coupled JSONL generation

Uses the `kbases` library's data types and `Jsonl.write` to generate
synthetic JSONL files. The benchmark depends on `kbases` and `unix`.

**Mechanism**

A single-file executable in `test-perf/`:

```
test-perf/
  dune
  perf_main.ml
```

Dune configuration:

```dune
(executable
 (name perf_main)
 (libraries kbases unix))

(rule
 (alias runperf)
 (deps %{bin:bs} (universe))
 (action (run ./perf_main.exe)))
```

`(deps %{bin:bs})` ensures `bs` is built before benchmarks run.
`(universe)` forces re-execution on every `dune build @runperf` —
benchmarks should never be cached. The executable can also be invoked
directly via `dune exec test-perf/perf_main.exe`.

**JSONL generation** constructs full `Data.Todo.t`, `Data.Note.t`, and
`Data.Relation.t` values and delegates to `Jsonl.write`:

```ocaml
let generate_jsonl ~path ~namespace ~num_todos ~num_notes ~num_relations =
  let todos = List.init num_todos (fun i ->
    Data.Todo.make
      (Data.Uuid.Typeid.make "todo")
      (Data.Identifier.make namespace 0)
      (Data.Title.make (Printf.sprintf "Todo %d" i))
      (Data.Content.make (Printf.sprintf "Content for todo %d" i))
      Data.Todo.Open) in
  let notes = List.init num_notes (fun i ->
    Data.Note.make
      (Data.Uuid.Typeid.make "note")
      (Data.Identifier.make namespace 0)
      (Data.Title.make (Printf.sprintf "Note %d" i))
      (Data.Content.make (Printf.sprintf "Content for note %d" i))
      Data.Note.Active) in
  let all_ids =
    Array.of_list (List.map Data.Todo.id todos @ List.map Data.Note.id notes) in
  let relations = List.init num_relations (fun i ->
    Data.Relation.make
      ~source:all_ids.(i mod Array.length all_ids)
      ~target:all_ids.((i + 1) mod Array.length all_ids)
      ~kind:(Data.Relation_kind.make "related") ~bidirectional:false) in
  ignore (Repository.Jsonl.write ~path ~namespace ~todos ~notes ~relations)
```

`Data.Todo.make` requires a niceid argument, but `Jsonl.write` does
not serialize niceids — `_todo_to_json` (`jsonl.ml:21–28`) reads only
`id`, `title`, `content`, and `status`. The `Data.Identifier.make
namespace 0` is a type-system artefact: `Data.Todo.t` includes
`niceid` as a field, so constructing a value requires it. TypeIds are
real UUIDv7s generated by `Typeid.make`, giving each run unique but
structurally identical data.

**Subprocess invocation** uses `Unix.create_process` directly, with a
`chdir` to place the process in the benchmark directory (required
because `Lifecycle.open_kb` locates the knowledge base via
`Git.find_repo_root` from the working directory):

```ocaml
let run_bs_timed ~dir ?stdin:content args =
  let exe = Lazy.force bs_exe in
  let argv = Array.of_list (exe :: args) in
  let saved_cwd = Sys.getcwd () in
  Unix.chdir dir;
  Fun.protect ~finally:(fun () -> Unix.chdir saved_cwd) (fun () ->
    let stdin_fd = match content with
      | None -> Unix.openfile "/dev/null" [Unix.O_RDONLY] 0
      | Some s ->
          let rd, wr = Unix.pipe () in
          ignore (Unix.write_substring wr s 0 (String.length s));
          Unix.close wr; rd in
    let devnull = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
    Fun.protect ~finally:(fun () -> Unix.close stdin_fd; Unix.close devnull)
      (fun () ->
        let t0 = Unix.gettimeofday () in
        let pid = Unix.create_process exe argv stdin_fd devnull devnull in
        let _, status = Unix.waitpid [] pid in
        let elapsed = Unix.gettimeofday () -. t0 in
        match status with
        | Unix.WEXITED 0 -> elapsed
        | _ -> Printf.ksprintf failwith "bs %s failed"
                 (String.concat " " args)))
```

The `chdir`/restore pattern is safe for the single-threaded benchmark
harness. Stdin is provided via a pipe for write operations (`bs add
todo "Title"` reads content from stdin). Stdout and stderr are
discarded to `/dev/null` — the benchmark cares only about timing, not
output.

A non-timed `run_bs` variant (same pattern, no timing) handles setup
commands (`bs init`, `bs rebuild`).

**State reset** between samples copies the baseline `.kbases.db` and
`.kbases.jsonl` back from saved copies:

```ocaml
let save_baseline ~dir =
  copy_file ~src:(db_path dir) ~dst:(db_path dir ^ ".baseline");
  copy_file ~src:(jsonl_path dir) ~dst:(jsonl_path dir ^ ".baseline")

let restore_baseline ~dir =
  copy_file ~src:(db_path dir ^ ".baseline") ~dst:(db_path dir);
  copy_file ~src:(jsonl_path dir ^ ".baseline") ~dst:(jsonl_path dir)
```

This is faster than re-running `bs rebuild` and gives an exact byte-
for-byte restoration. The copy cost is negligible relative to the
operations being benchmarked.

**Statistics** compute median, min, max, and standard deviation from
the collected sample array. **Reporting** prints one line per tier in
the format shown in the scenarios section (e.g., `10000 items
median 42.3ms  min 40.1ms  max 47.8ms  stddev 2.9ms`).

**Scenario structure** — each scenario follows a uniform pattern:

```ocaml
let scenario_single_add ~samples tiers =
  Printf.printf "--- single-add-todo (%d samples, 1 warm-up) ---\n" samples;
  List.iter (fun n_items ->
    with_benchmark_dir (fun dir ->
      populate ~dir ~n_items;
      save_baseline ~dir;
      (* warm-up *)
      ignore (run_bs_timed ~dir ~stdin:"warmup" ["add"; "todo"; "Warmup"]);
      restore_baseline ~dir;
      (* timed samples *)
      let timings = List.init samples (fun _ ->
        restore_baseline ~dir;
        run_bs_timed ~dir ~stdin:"bench" ["add"; "todo"; "Bench"]) in
      print_tier ~n_items (compute_stats timings))
  ) tiers
```

`with_benchmark_dir` creates a temp directory containing `.git/`,
runs `bs init`, and cleans up afterward — mirroring the integration
test helper's `with_git_root` / `init_kb` pattern. `populate`
generates a JSONL file and runs `bs rebuild`.

**What changes for consumers** — nothing. The benchmark does not
modify any `bs` source code or public interface.

**What changes for tests** — existing tests are unaffected. The
`test-perf/` directory is independent of `@runtest` and `@runcheck`.
A new `@runperf` alias is the sole entry point.

**Limitations**

- The benchmark depends on `kbases` library internals:
  `Data.Todo.make` takes a niceid that is meaningless in this context.
  If the data types change (e.g., `make` gains or drops a parameter),
  the benchmark must be updated even though the change is unrelated to
  performance.
- TypeIds are nondeterministic. Each run generates different data,
  which means JSONL files differ between runs. This doesn't affect
  measurement quality (the workloads are structurally identical), but
  makes debugging harder — you can't diff two runs' input data.
- After rebuild, niceid assignment depends on the sort order of
  random TypeIds. The entity assigned `kb-0` varies between runs.
  Scenario 5 (`bs show`) must discover which niceid to target (e.g.,
  by parsing `bs list --json` output) rather than hardcoding it.

**Research needed** — none. The library APIs, JSONL format, and
TypeId validation are fully understood from the background section.

### Approach B: Self-contained JSONL generation

Generates JSONL via raw `Yojson.Safe` JSON construction with no
dependency on the `kbases` library. The benchmark executable depends
only on `yojson` and `unix`.

**Mechanism**

Same directory layout and scenario structure as Approach A. The dune
configuration drops the `kbases` dependency:

```dune
(executable
 (name perf_main)
 (libraries unix yojson))

(rule
 (alias runperf)
 (deps %{bin:bs} (universe))
 (action (run ./perf_main.exe)))
```

TypeIds are deterministic zero-padded integers:

```ocaml
let todo_typeid i = Printf.sprintf "todo_%026d" i
let note_typeid i = Printf.sprintf "note_%026d" i
```

These satisfy `Typeid.parse` validation: the suffix is 26 characters
of valid Crockford Base32 digits (decimal 0–9 are all valid base32
characters), and `Base32.decode` produces a 128-bit value that
`Uuidm.of_binary_string` accepts as a valid UUID. They are not real
UUIDv7s — they lack the version and variant bits — but no code path
in `bs` checks UUIDv7 structure after the TypeId is parsed.
Validation was traced through `Typeid.parse` → `of_string` →
`validate_suffix` → `Base32.decode` → `Uuidm.of_binary_string`.

**JSONL generation** constructs JSON objects directly, replicating the
format produced by `Jsonl.write` (`jsonl.ml:68–95`):

```ocaml
let generate_jsonl ~path ~namespace ~num_todos ~num_notes ~num_relations =
  let todos = List.init num_todos (fun i ->
    (todo_typeid i, `Assoc [
       ("type", `String "todo"); ("id", `String (todo_typeid i));
       ("title", `String (Printf.sprintf "Todo %d" i));
       ("content", `String (Printf.sprintf "Content for todo %d" i));
       ("status", `String "open")])) in
  let notes = List.init num_notes (fun i ->
    (note_typeid i, `Assoc [
       ("type", `String "note"); ("id", `String (note_typeid i));
       ("title", `String (Printf.sprintf "Note %d" i));
       ("content", `String (Printf.sprintf "Content for note %d" i));
       ("status", `String "active")])) in
  let relations = List.init num_relations (fun i ->
    let src = todo_typeid (i mod max 1 num_todos) in
    let tgt = note_typeid (i mod max 1 num_notes) in
    let key = Printf.sprintf "relation:%s:%s:related" src tgt in
    (key, `Assoc [
       ("type", `String "relation"); ("source", `String src);
       ("target", `String tgt); ("kind", `String "related");
       ("bidirectional", `Bool false)])) in
  let sorted = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2)
    (todos @ notes @ relations) in
  let lines = List.map (fun (_, j) -> Yojson.Safe.to_string j) sorted in
  let entity_content = String.concat "\n" lines in
  let content_hash = Digest.string entity_content |> Digest.to_hex in
  let header = Yojson.Safe.to_string (`Assoc [
    ("_kbases", `String "1"); ("namespace", `String namespace);
    ("entity_count", `Int (List.length sorted));
    ("content_hash", `String content_hash)]) in
  let oc = open_out path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () ->
    Printf.fprintf oc "%s\n%s\n" header entity_content)
```

This replicates five aspects of `Jsonl.write`: the sort-key scheme
(TypeId string for todos/notes, `"relation:src:tgt:kind"` for
relations), the `String.compare` sort, the `"\n"`-joined entity
content for hashing, the MD5 content hash via `Digest`, and the
header format. Any change to these in `jsonl.ml` must be mirrored
here.

Deterministic TypeIds make sort order predictable. After rebuild,
niceids are assigned in JSONL sort order: notes first (`n` < `r` <
`t` in ASCII), then todos. `note_00000000000000000000000000` gets
`kb-0`, `todo_00000000000000000000000000` gets `kb-<num_notes>`.
Scenario 5 can hardcode the target niceid. To ensure `kb-0` is the
target of a relation, the generation places `note_typeid 0` as a
relation target.

All other infrastructure — subprocess invocation, timing, state
reset, statistics, reporting, scenario structure — is identical to
Approach A.

**What changes for consumers** — nothing.

**What changes for tests** — same as Approach A: no impact on
existing tests. New `@runperf` alias only.

**Limitations**

- Duplicates JSONL format knowledge. The sort-key scheme, field
  names, content hash computation, and file structure are defined in
  `Jsonl.write` and replicated here. If the JSONL format changes,
  both `jsonl.ml` and the benchmark must be updated — but the
  compiler won't flag the mismatch. The benchmark would fail at
  runtime when `bs rebuild` rejects the invalid JSONL.
- The runtime failure mode is clear (rebuild fails immediately with a
  parse error), so drift is caught early — but it requires running
  the benchmark to discover the problem.
- Deterministic TypeIds are not real UUIDv7s. If any future code path
  validates UUIDv7 structure (version/variant bits), these TypeIds
  would fail. Currently no such validation exists.

**Research needed** — none. TypeId validation was traced end-to-end,
confirming that deterministic zero-padded decimal TypeIds pass all
checks. The JSONL format is fully specified in `jsonl.ml` and can be
replicated without ambiguity.

## Design Decisions

1. **Black-box benchmark via subprocess invocation.** The benchmark
   invokes `bs` as a subprocess rather than calling library functions
   directly. This measures the same path that users and agents
   experience. The alternative — library-level benchmarks that call
   `Kb_service` functions in-process — was considered and rejected
   because it would bypass process-spawn overhead, startup sync, and
   CLI argument parsing, all of which are part of the real-world cost.
   Both approaches agree on this; it is not a point of differentiation.

2. **`Unix.create_process` over `Sys.command`.** The existing
   integration test helper uses `Sys.command`, which spawns a shell
   intermediary. The benchmark uses `Unix.create_process` to eliminate
   shell overhead from timing measurements. This is a deliberate
   departure from the integration test pattern — the integration tests
   don't care about sub-millisecond timing, but the benchmark does.

3. **File-copy state reset over re-rebuild.** Between samples, the
   benchmark copies pre-saved `.kbases.db` and `.kbases.jsonl` files
   back into place rather than re-running `bs rebuild`. File copy is
   O(file-size) with no parsing, validation, or SQL — faster and more
   predictable than re-running the O(n) rebuild path. This keeps
   inter-sample reset cost negligible relative to the operations being
   measured.

4. **Deterministic vs. random synthetic data.** Approach A generates
   real UUIDv7 TypeIds (nondeterministic), while Approach B uses
   zero-padded integer TypeIds (deterministic). This is the most
   consequential divergence between the approaches. Deterministic data
   makes niceid assignment predictable (enabling hardcoded niceids in
   scenario 5), makes runs reproducible (identical JSONL files every
   time), and simplifies debugging (input data can be diffed between
   runs). Nondeterministic data exercises a wider range of TypeId
   values but adds no measurement value — the benchmark measures I/O
   and serialization cost, neither of which varies with TypeId content.
   Deterministic TypeIds are preferred.

## Consequences and Trade-offs

**Coupling surface.** Approach A couples the benchmark to `kbases`
library internals — specifically `Data.Todo.make`, `Data.Note.make`,
`Data.Relation.make`, and `Repository.Jsonl.write`. These are stable
interfaces, but the coupling is semantically inappropriate: the
benchmark must supply a niceid (`Data.Identifier.make namespace 0`)
that `Jsonl.write` ignores entirely. `_todo_to_json` serializes `id`,
`title`, `content`, and `status` — not `niceid`. The dummy niceid is
a type-system tax with no functional purpose. If `Data.Todo.make`
gains or drops a parameter, the benchmark breaks despite the change
being unrelated to performance. Approach B avoids this entirely by
constructing JSON directly — the benchmark has no opinion about the
shape of `Data.Todo.t`.

In the other direction, Approach B duplicates format knowledge: the
sort-key scheme, field names, content-hash computation, and header
structure are all defined in `jsonl.ml` and replicated in the
benchmark. If the JSONL format changes, the benchmark must be updated
manually. However, the failure mode is clear and immediate — `bs
rebuild` rejects the stale JSONL with a parse error on the next
benchmark run. There is no silent drift.

**Reproducibility.** Approach B produces identical JSONL files across
runs. Two benchmark runs against the same tier generate byte-identical
input data, and after rebuild, niceid assignment follows the same
deterministic order. This aids debugging (diff two runs' databases),
simplifies scenario 5 (hardcode the target niceid rather than
discovering it at runtime), and makes results more comparable across
machines. Approach A generates different UUIDv7s each run, so input
data, sort order, and niceid assignment all vary.

**Maintenance when `bs` evolves.** Approach A automatically picks up
changes to the data model (new fields, renamed types) through
compile-time errors — if `Data.Todo.make` changes, the benchmark
fails to compile. Approach B picks up JSONL format changes through
runtime errors — if the format changes, `bs rebuild` fails during the
benchmark. Both catch drift; they differ in when. Compile-time
detection is earlier, but the frequency of JSONL format changes is low
(the format has been stable since inception), and a runtime failure
during `bs rebuild` is unambiguous and fast — it occurs during setup
before any timing runs.

**Dependency footprint.** Approach A depends on `kbases`, `unix`,
and transitively on every dependency of `kbases` (including `sqlite3`,
`cmdliner`, `uuidm`, etc.). Approach B depends on `yojson` and `unix`
only. A lighter dependency footprint means faster compilation of the
benchmark executable and less exposure to unrelated build breakage.
This is a minor advantage in practice — `kbases` compiles quickly —
but it reflects the principle that test infrastructure should depend
on as little of the system under test as possible.

**Niceid predictability.** With Approach B's deterministic TypeIds,
niceids after rebuild follow a predictable order: notes sort before
relations sort before todos (ASCII order of `n` < `r` < `t`), so
`note_00...00` gets `kb-0`, `note_00...01` gets `kb-1`, etc.
Scenario 5 can hardcode the niceid and guarantee the target is a
relation target by placing `note_typeid 0` as a relation target during
generation. Approach A must discover the niceid at runtime by parsing
`bs list` output, adding code complexity to the benchmark harness for
no measurement benefit.

## Requirement Coverage

Coverage analysis for Approach B (the recommended approach):

| # | Requirement | How satisfied |
|---|-------------|---------------|
| 1 | Single-operation latency at scale | Scenario 1 (write) and scenario 5 (read). Three tiers for writes, 10K for reads. State reset between samples via file copy. |
| 2 | Sequential throughput | Scenarios 2 (empty) and 3 (10K). 50 sequential `add todo` calls per sample; state reset between samples. |
| 3 | Rebuild time at scale | Scenario 4. Three tiers (100, 1K, 10K). DB deleted and re-initialized between samples. |
| 4 | Report, don't assert | All scenarios print timing results. No threshold-based assertions. |
| 5 | Separate from `runtest` | `@runperf` alias. `test-perf/` directory independent of `@runtest` and `@runcheck`. |
| 6 | Deterministic JSONL setup | `generate_jsonl` constructs JSONL programmatically. `bs rebuild` populates the database. Setup time excluded from reported timings. |
| 7 | CLI-only via `Unix.create_process` | `run_bs_timed` uses `Unix.create_process`. No library-level benchmarks. |
| 8 | Heterogeneous entity mix | Default mix: ~40% todos, ~40% notes, ~20% relations. Scenario 7 compares homogeneous vs. heterogeneous. |
| 9 | Multiple samples with statistics | Configurable sample count (default 5). Reports median, min, max, stddev. |
| 10 | Warm-up run | One discarded invocation before timed samples in every scenario. |

All requirements are fully satisfied. No compromises.

## Recommendation

**Approach B: Self-contained JSONL generation.**

The benchmark is a black-box observer of `bs` CLI behavior. Its setup
code — generating synthetic JSONL files — should depend on the file
format specification, not on the library that implements the system
under test. Approach B honours this boundary. It produces deterministic,
reproducible input data; it avoids the spurious niceid coupling that
Approach A inherits from `Data.Todo.make`; and it keeps the dependency
footprint minimal.

The cost is duplicated format knowledge. This is real but bounded: the
JSONL format is simple (a header line plus sorted JSON objects with an
MD5 hash), stable (unchanged since inception), and any drift is caught
immediately when `bs rebuild` rejects the stale file. The benchmark
will not silently produce wrong results — it will fail loudly during
setup.

Approach A remains available as a fallback if the JSONL format begins
evolving frequently enough that manual synchronization becomes
burdensome. In that scenario, coupling to the library's serialization
code would trade format-drift risk for type-change risk — a reasonable
trade-off when the format is volatile. Under current conditions, where
the format is stable and the data types are still evolving, Approach B
is the better choice.
