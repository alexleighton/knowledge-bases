# Design: JSONL Header for Git Automerge

## Problem Statement

The `.kbases.jsonl` file is designed to be git-friendly: each entity
occupies one line, sorted by TypeId, so that independent additions on
separate branches merge cleanly with git's standard text merge
machinery (UC-11 in the product requirements).

The header line undermines this. Today it looks like:

```json
{"_kbases":"1","namespace":"kb","entity_count":74,"content_hash":"10465acd5273886682b2c515eadb4d45"}
```

Both `entity_count` and `content_hash` change on every flush. When
two branches independently add items, line 1 is modified on both
sides with different values, producing a guaranteed merge conflict.
Git cannot resolve this automatically — it cannot know to sum the
counts or recompute the hash. This forces manual conflict resolution
on every merge that touches the knowledge base, which defeats the
purpose of the JSONL format.

The entity lines below the header merge correctly. The header is the
only source of merge conflicts in normal operation.

## Background

### Current state

The JSONL file is the git-tracked, canonical representation of a
knowledge base. It consists of a header line followed by one JSON
object per entity (todo, note, or relation), sorted lexicographically
by a sort key derived from the entity's TypeId. The file lives at the
git root as `.kbases.jsonl`.

The header is a JSON object on line 1 with four fields:

```json
{"_kbases":"1","namespace":"kb","entity_count":74,"content_hash":"10465acd5273886682b2c515eadb4d45"}
```

Two of these fields (`_kbases` and `namespace`) are stable across
flushes — they are set once during `bs init` and never change. The
other two (`entity_count` and `content_hash`) change on every flush.

The `content_hash` is an MD5 digest (via OCaml's `Digest` module) of
the concatenated entity lines — not the whole file. Specifically,
`Jsonl.write` (line 78–79 of `lib/repository/jsonl.ml`) computes it
as:

```ocaml
let entity_content = String.concat "\n" entity_lines in
let content_hash = Digest.string entity_content |> Digest.to_hex in
```

The hash covers entity content only; the header line is excluded from
the digest input. This is important because the header itself contains
the hash — hashing the whole file would be self-referential.

The `entity_count` is simply `List.length sorted` — the number of
entity lines written. It is not validated during parsing; `Jsonl.read`
processes whatever entity lines are present regardless of what the
header claims.

### Relevant architecture

The change touches three layers of the codebase:

**Repository layer** — `Jsonl` module
(`lib/repository/jsonl.ml`, 237 lines):

- `header` type (line 8–13): Record with `version`, `namespace`,
  `entity_count`, `content_hash`. Exposed in the `.mli`.
- `write` (line 68–95): Serializes entities to JSONL. Computes
  `content_hash` over entity lines, writes the header with all four
  fields, returns the hash as `Ok content_hash`.
- `read` (line 216–225): Parses the full file — header + entities.
  Returns `(header, entity_record list)`.
- `read_header` (line 227–236): Reads only line 1 and parses it as a
  header. Exists as an optimization so `rebuild_if_needed` can check
  the hash without parsing the entire file.
- `_parse_header_json` (line 126–136): Requires all four fields. A
  missing `entity_count` or `content_hash` produces a `Parse_error`.

**Repository layer** — `Config` module
(`lib/repository/config.ml`, 66 lines):

A key-value store backed by SQLite table
`config(key TEXT PRIMARY KEY, value TEXT NOT NULL)`. Currently stores
three keys: `namespace`, `content_hash`, and `dirty`. The
`content_hash` key holds the most recently stored hash for rebuild
comparison.

**Service layer** — `Sync_service`
(`lib/service/sync_service.ml`, 146 lines):

Orchestrates the two synchronization directions:

- `flush` (line 63–82): Queries all entities from SQLite, calls
  `Jsonl.write`, stores the returned `content_hash` in config, clears
  the dirty flag.
- `force_rebuild` (line 93–129): Reads the full JSONL file via
  `Jsonl.read`, deletes all SQLite data, reimports all entities, then
  stores `header.content_hash` in config and clears dirty.
- `rebuild_if_needed` (line 131–146): The rebuild detection logic.
  Reads only the header (`Jsonl.read_header`), retrieves the stored
  hash from config, and compares:
  - No stored hash → `force_rebuild`.
  - Stored hash ≠ header hash → `force_rebuild`.
  - Hashes match + dirty → `flush`.
  - Hashes match + not dirty → no-op.

**Service layer** — `Kb_service`
(`lib/service/kb_service.ml`, 159 lines):

The main service facade. Every write operation (`add_note`, `add_todo`,
`update`, `resolve`, `archive`, `relate`) goes through `_with_flush`
(line 82–93), which calls `mark_dirty` before the operation and
`flush` after it. The `open_kb` function (line 95–108) creates a
`Sync_service` and calls `rebuild_if_needed` on every KB open, meaning
rebuild detection runs on every `bs` invocation.

**CLI layer** — `App_context` (`bin/app_context.ml`, 18 lines):

Calls `Kb_service.open_kb()` in its `init` function. Every `bs`
subcommand (except `init`) goes through `App_context.init`, triggering
the full `rebuild_if_needed` path.

The `cmd_flush.ml` and `cmd_rebuild.ml` (31 lines each) are thin CLI
wrappers that call `Kb_service.flush` and `Kb_service.force_rebuild`
respectively.

### Data flow: rebuild detection

```
bs <any command>
  → App_context.init()
    → Kb_service.open_kb()
      → Sync_service.rebuild_if_needed
        → Jsonl.read_header ~path      ← reads 1 line only
        → Config.get "content_hash"    ← reads from SQLite
        → compare header hash vs stored hash
        → mismatch → force_rebuild (full JSONL read + reimport)
```

The key property: `rebuild_if_needed` currently reads only the first
line of the JSONL file for comparison. It never reads the full file
unless a rebuild is actually needed. This is the fast path that
`read_header` exists to support.

### Data flow: flush

```
Kb_service._with_flush
  → Sync_service.mark_dirty         (config set "dirty" "true")
  → <write operation>
  → Sync_service.flush
    → Repository queries: list_all todos, notes, relations
    → Jsonl.write
      → sort entities by TypeId-derived key
      → serialize to JSON lines
      → hash = MD5(joined entity lines)
      → write header + entities atomically (tmp + rename)
      → return hash
    → Config.set "content_hash" hash
    → Config.set "dirty" "false"
```

### Existing patterns

**Atomic file writes**: `Jsonl.write` uses a tmp-file-then-rename
pattern (line 87–91). Any new file-hashing logic will see a
consistent file state.

**Hash-before-store**: Both `flush` and `force_rebuild` store the
content hash in config immediately after a successful write or read.
The hash and the file are always in sync within a single `bs`
invocation.

**Dirty flag gating**: `flush` is a no-op when the dirty flag is not
set (line 65–66). `_with_flush` calls `mark_dirty` before every write
operation and `flush` after. The explicit `bs flush` command in
`Kb_service.flush` (line 146–152) always sets dirty before flushing,
so it always does real work.

### Tests and coverage

The affected areas have the following test coverage:

**`test/repository/jsonl_expect.ml`** (145 lines, 5 expect tests):
Round-trip write/read, content hash determinism, `read_header`,
empty entities, and parse error on unknown type. Three tests assert
on `entity_count` or `content_hash` in header fields. One test
(line 120) constructs a raw JSONL header string with `entity_count`
and `content_hash` hardcoded.

**`test/service/sync_service_expect.ml`** (186 lines, 6 expect
tests): Tests for `flush` (writes file, skips when not dirty, updates
hash in config), `force_rebuild` (replaces DB from JSONL),
`rebuild_if_needed` (hash mismatch detection, hash match no-op, no
JSONL file no-op). Two tests read `content_hash` from config to
verify it was stored. One test asserts on `header.entity_count`.

**`test-integration/flush_expect.ml`** (62 lines, 4 tests):
Integration tests for the `bs flush` command — after adding entities,
on empty KB, outside git repo, and `--json` output.

**`test-integration/rebuild_expect.ml`** (58 lines, 4 tests):
Integration tests for `bs rebuild` — restores entities, no JSONL
file error, outside git repo, and `--json` output.

**`test-perf/perf_harness.ml`** (246 lines): Performance test
harness containing `generate_jsonl` (line 38–80), which duplicates
the JSONL format including `entity_count` and `content_hash` in the
header. This code is independent of the `Jsonl` module — it
constructs JSONL files directly using `Yojson` to avoid coupling to
the library.

### Observations

1. **`entity_count` is write-only.** The parser stores it in the
   header record, but no code path reads `header.entity_count` for
   any logic. `Jsonl.read` processes whatever entity lines exist
   (line 224: filters non-empty lines and parses each one). The count
   appears only in test assertions that verify the header was parsed
   correctly. Removing it from the header has no functional impact.

2. **`content_hash` serves exactly one purpose**: rebuild detection
   in `Sync_service.rebuild_if_needed`. It is written by `flush` and
   `force_rebuild`, and read back by `rebuild_if_needed`. Moving the
   hash computation from the JSONL file to a whole-file hash replaces
   the one consumer.

3. **`read_header` exists solely for the current rebuild detection
   fast path.** It is called in exactly one place:
   `Sync_service.rebuild_if_needed` (line 136). If rebuild detection
   switches to hashing the whole file, `read_header` loses its only
   caller. The function would still work (returning version and
   namespace), but nothing would use it.

4. **The `Jsonl.write` return type is coupled to the hash.** It
   currently returns `(string, error) result` where the `string` is
   the content hash. `Sync_service.flush` captures this return value
   and stores it in config. If the hash moves to a whole-file
   computation, `write` no longer needs to return a hash — its job
   is just to write the file.

5. **The performance test harness duplicates the JSONL format.**
   `perf_harness.ml` generates JSONL files independently of the
   `Jsonl` module, replicating the header structure including
   `entity_count` and `content_hash`. Any header format change
   requires updating this duplication. The duplication is deliberate
   (documented in `note_01kjmcfshqeyqrf5fjv03z8pxt`: "Approach B —
   self-contained JSONL generation... format duplication is bounded
   and drift is caught immediately by bs rebuild").

6. **The `_parse_header_json` function is strict.** It requires all
   four fields and returns `Parse_error` for any missing field. To
   handle old-format headers gracefully (requirement 6), the parser
   must change from requiring `entity_count` and `content_hash` to
   ignoring them if present. This is a change in the parsing logic
   at line 126–136.

7. **Flush happens on every write operation.** Because `_with_flush`
   wraps all six write operations in `Kb_service`, the header —
   including `entity_count` and `content_hash` — is rewritten after
   every single `bs add`, `bs update`, `bs resolve`, `bs archive`,
   and `bs relate`. This amplifies the merge conflict problem: not
   just "both branches modified the KB" but "both branches ran any
   write command at all".

8. **The hash stored in config after `force_rebuild` comes from the
   JSONL header, not from hashing the file.** At line 128 of
   `sync_service.ml`: `_set_config t "content_hash"
   header.Jsonl.content_hash`. This means the stored hash is the
   entity-only MD5 from inside the file, not a hash of the file
   itself. A whole-file hash approach would need to actually read
   and hash the file bytes.

9. **The product requirements JSONL design considerations section**
   (lines 448–471 of `docs/product-requirements.md`) discusses
   snapshot vs. journal format and sorting for merge clarity, but
   does not mention the header format or the merge conflict it
   causes. The section does not document rebuild detection or the
   role of `content_hash`. Requirement 5 asks for this section to be
   updated.

10. **File counts for the change.** Source files that reference
    `content_hash`: 3 production (`jsonl.ml`, `jsonl.mli`,
    `sync_service.ml`), 2 test (`jsonl_expect.ml`,
    `sync_service_expect.ml`), 1 perf (`perf_harness.ml`). Source
    files that reference `entity_count`: 2 production (`jsonl.ml`,
    `jsonl.mli`), 2 test (`jsonl_expect.ml`,
    `sync_service_expect.ml`), 1 perf (`perf_harness.ml`). The
    `sync_service.mli` documents the behavior but does not name the
    fields. Total: 8 files will need changes (3 production, 2 test,
    1 perf, 1 docs, 1 interface).

## Requirements

1. **Remove `entity_count` from the JSONL header.** The field is not
   validated during read (the parser processes whatever entities are
   present) and nothing external consumes it. Removing it eliminates
   one source of merge conflicts with no loss of functionality.

2. **Remove `content_hash` from the JSONL header.** The hash changes
   on every flush, guaranteeing a merge conflict whenever both
   branches modify the KB. The rebuild-detection mechanism that
   depends on this hash must be preserved through an alternative
   approach (requirement 3).

3. **Preserve rebuild detection using a whole-file hash computed at
   runtime.** After a git merge or pull, `rebuild_if_needed` must
   still detect that the JSONL file has changed and trigger a
   rebuild. The new mechanism:

   - Hashes the entire file contents (not just entity lines) at
     three points: `rebuild_if_needed` (compare against stored
     hash), `flush` (hash after write, store), and `force_rebuild`
     (hash after read, store).
   - Stores the resulting hash in SQLite config, as today.
   - Uses the full file bytes for hashing. If the header ever gains
     a new stable field, that change will correctly trigger a
     rebuild.

   _Rationale_: Rebuild is expensive at scale (~1s at 1,000 items,
   ~19s at 10,000). Hashing a text file is negligible by comparison
   (single-digit milliseconds even for large KBs). Full-file
   hashing is simpler than entity-only hashing (no parsing needed
   to separate header from content) and correctly detects any file
   change. Refined after resolving open question: full-file hash
   chosen over entity-only hash.

4. **The header line must contain only fields that are stable across
   flushes within a repository.** Currently that means `_kbases`
   (version) and `namespace`. Both branches will write identical
   values for these fields, so git sees no conflict on line 1.

5. **Change `Jsonl.write` to return `unit` instead of the content
   hash.** With the hash no longer embedded in the file, `write`'s
   responsibility is writing the file — nothing more. The caller
   (`Sync_service.flush`) hashes the written file and stores the
   result. This decouples the write operation from rebuild
   detection. Added after codebase analysis showed `write`'s return
   type is coupled to the in-header hash (observation 4).

6. **Remove `Jsonl.read_header`.** The function exists solely to
   support the current rebuild detection fast path (reading line 1
   to extract the hash for comparison). With whole-file hashing,
   rebuild detection hashes the entire file rather than reading
   the header separately. `read_header` has no remaining callers.
   Added after codebase analysis showed `read_header` is called in
   exactly one place (observation 3).

7. **The parser must handle old-format headers gracefully during
   transition.** When encountering `entity_count` or `content_hash`
   fields in the header, the parser should ignore them rather than
   error. This allows the new code to read old-format files without
   requiring a manual migration step.

   _Rationale_: Forward tolerance is cheap to implement (stop
   requiring the fields) and avoids a sharp migration edge.

8. **Update the product requirements** (`docs/product-requirements.md`)
   to explicitly state that the JSONL header must not contain
   per-flush-varying fields, and to document the whole-file hash
   approach to rebuild detection. The JSONL design considerations
   section (lines 448–471) should reflect the lesson learned:
   anything in the file that changes on every write is a merge
   conflict waiting to happen.

## Scenarios

### S1: Clean merge after independent additions

**Before (current behavior):**

```
Branch A: adds 2 todos, flushes → header has entity_count:76, content_hash:"aaa..."
Branch B: adds 1 note,  flushes → header has entity_count:75, content_hash:"bbb..."
git merge → CONFLICT on line 1 of .kbases.jsonl
```

**After (new behavior):**

```
Branch A: adds 2 todos, flushes → header is {"_kbases":"1","namespace":"kb"}
Branch B: adds 1 note,  flushes → header is {"_kbases":"1","namespace":"kb"}
git merge → line 1 identical on both sides, no conflict
           entity lines merge cleanly (distinct TypeIds, sorted)
```

### S2: Rebuild detection after merge

```
$ git merge feature-branch          # JSONL file changes
$ bs list                           # first bs invocation after merge
  → bs reads .kbases.jsonl, hashes the whole file
  → compares hash against stored hash in SQLite config
  → hashes differ → triggers force_rebuild
  → stores new hash in config
$ bs list                           # subsequent invocation
  → hashes file again, matches stored hash → skips rebuild
```

### S3: Reading an old-format file with new code

```
# Old header:
{"_kbases":"1","namespace":"kb","entity_count":74,"content_hash":"10465..."}

$ bs list   # new code reads old file
  → parser sees entity_count and content_hash, ignores them
  → reads entities normally
  → rebuild proceeds, stores whole-file hash in config
$ bs flush  # writes new format
  → header is now {"_kbases":"1","namespace":"kb"}
```

### S4: Flush on a clean knowledge base

```
$ bs add todo "New task"
  → SQLite updated, dirty flag set
$ bs flush
  → reads all entities from SQLite
  → sorts, serializes to JSONL
  → header contains only _kbases and namespace
  → writes file atomically (tmp + rename)
  → hashes the written file, stores hash in SQLite config
  → clears dirty flag
```

## Constraints

- The JSONL entity format (todo, note, relation lines) must not
  change. Only the header line changes.
- `bs rebuild` and `bs flush` must continue to work as documented.
- No new runtime dependencies.
- The SQLite config table schema does not change (it already stores
  key-value pairs including `content_hash`).

## Open Questions

None at this stage. The two first-pass open questions were resolved
during refinement:

- **Full-file vs entity-only hashing** → Full-file. Simpler (no
  parsing to separate header from content), and any header change
  should trigger a rebuild. Incorporated into requirement 3.
- **Keep `read_header`?** → Remove it. Its sole caller
  (`rebuild_if_needed`) will hash the whole file instead of reading
  just the header. Incorporated as requirement 6.

## Approaches

The requirements are prescriptive: they specify *what* changes (remove
fields, whole-file hash, return unit, remove `read_header`) and *where*
the hash moves (to runtime computation in `Sync_service`). This leaves
one viable approach rather than a family of alternatives. An approach
that keeps the hash inside `write`'s return type, for instance, would
contradict requirement 5. One that keeps `read_header` would
contradict requirement 6. The approach below is the natural — and
only — way to satisfy all eight requirements simultaneously.

### Approach A: Whole-file hash at the service layer

The header shrinks to two stable fields. Hash computation moves out
of `Jsonl` entirely and into `Sync_service`, where it operates on
the whole file via `Digest.file`.

#### Mechanism

**Header type** becomes:

```ocaml
type header = {
  version   : int;
  namespace : string;
}
```

**Header serialization** drops the volatile fields:

```ocaml
let _header_to_json ~namespace =
  `Assoc [
    ("_kbases", `String "1");
    ("namespace", `String namespace);
  ]
```

**Header parsing** stops requiring `entity_count` and `content_hash`.
Old-format headers with these fields are parsed successfully — the
fields are simply not extracted:

```ocaml
let _parse_header_json json =
  let open Data.Result.Syntax in
  let* version_s = _get_string json "_kbases" in
  let* () =
    if String.equal version_s "1" then Ok ()
    else Error (Parse_error (Printf.sprintf "unsupported JSONL version: %S" version_s))
  in
  let* namespace = _get_string json "namespace" in
  Ok { version = 1; namespace }
```

This satisfies requirement 7 (old-format tolerance) by construction:
the parser only reads `_kbases` and `namespace`, ignoring any
additional fields in the JSON object.

**`Jsonl.write`** returns `(unit, error) result`. The hash computation
(lines 78–79 of the current `jsonl.ml`) and the `entity_count`
binding (line 80) are removed. The function assembles the file
content and writes it atomically, nothing more:

```ocaml
let write ~path ~namespace ~todos ~notes ~relations =
  try
    let keyed = (* ... sort as before ... *) in
    let sorted = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) keyed in
    let entity_lines =
      List.map (fun (_, json) -> Yojson.Safe.to_string json) sorted in
    let header_json = _header_to_json ~namespace in
    let header_line = Yojson.Safe.to_string header_json in
    let entity_count = List.length sorted in
    let full_content =
      if entity_count = 0 then header_line ^ "\n"
      else header_line ^ "\n" ^ String.concat "\n" entity_lines ^ "\n"
    in
    let tmp_path = path ^ ".tmp" in
    let oc = open_out tmp_path in
    Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      output_string oc full_content);
    Unix.rename tmp_path path;
    Ok ()
  with
  | Sys_error msg -> Error (Io_error msg)
  | exn -> Error (Io_error (Printexc.to_string exn))
```

Note: `entity_count` is still computed as a local binding for the
empty-file branch (`if entity_count = 0`), but it is no longer
written into the header or exposed to callers.

**`Jsonl.read_header`** is removed (requirement 6). Its only caller
was `Sync_service.rebuild_if_needed`.

**`Sync_service`** gains a file-hashing helper:

```ocaml
let _hash_file path =
  try Ok (Digest.file path |> Digest.to_hex)
  with Sys_error msg -> Error (Sync_failed ("hash error: " ^ msg))
```

`Digest.file` reads the file and computes its MD5 digest. It is
part of the OCaml standard library (`Digest` module, line 68 of
`digest.mli`), already used in this codebase via `Digest.string`.
`Digest.file` is not deprecated in OCaml 5.3.

The three call sites change:

**`flush`** — calls `Jsonl.write` (now returns unit), then hashes the
written file and stores the hash:

```ocaml
let flush t =
  let open Data.Result.Syntax in
  let* dirty = _is_dirty t in
  if not dirty then Ok ()
  else
    let* todos = (* ... as before ... *) in
    let* notes = (* ... as before ... *) in
    let* relations = (* ... as before ... *) in
    let* namespace = _get_namespace t in
    let* () =
      Jsonl.write ~path:t.jsonl_path ~namespace ~todos ~notes ~relations
      |> Result.map_error _map_jsonl_error in
    let* file_hash = _hash_file t.jsonl_path in
    let* () = _set_config t "content_hash" file_hash in
    _set_config t "dirty" "false"
```

**`force_rebuild`** — after reading and importing all entities, hashes
the file and stores the result. The hash comes from the file on disk,
not from the parsed header:

```ocaml
(* end of force_rebuild, replacing the current line 128 *)
let* file_hash = _hash_file t.jsonl_path in
let* () = _set_config t "content_hash" file_hash in
_set_config t "dirty" "false"
```

**`rebuild_if_needed`** — hashes the file and compares against the
stored hash. No header parsing needed:

```ocaml
let rebuild_if_needed t =
  let open Data.Result.Syntax in
  if not (Sys.file_exists t.jsonl_path) then Ok ()
  else
    let* file_hash = _hash_file t.jsonl_path in
    let* stored_hash = _get_config t "content_hash" in
    match stored_hash with
    | None -> force_rebuild t
    | Some hash when not (String.equal hash file_hash) ->
        force_rebuild t
    | Some _ ->
        let* dirty = _is_dirty t in
        if dirty then flush t else Ok ()
```

#### One-time rebuild on upgrade

After upgrading, the first `rebuild_if_needed` invocation will
always trigger a rebuild. The stored hash (entity-only MD5 from the
old code) will never match the new whole-file MD5. This is correct
and desirable: the rebuild rewrites the JSONL file with the new
header format (no `entity_count` or `content_hash`), and the new
whole-file hash is stored in config. Subsequent invocations match
normally. The one-time rebuild is the same cost as any other rebuild
— noticeable at scale but not problematic.

#### What changes for consumers

- **`Jsonl.header` type** loses `entity_count` and `content_hash`.
  Code accessing these fields gets a compile error, making it
  impossible to miss an update site.

- **`Jsonl.write` signature** changes from
  `... -> (string, error) result` to `... -> (unit, error) result`.
  Callers that bound the result (`let* content_hash = Jsonl.write ...`)
  change to `let* () = Jsonl.write ...`.

- **`Jsonl.read_header`** is removed from the `.mli`. Its sole caller
  is updated as part of this change.

- **External behavior** is unchanged. `bs flush`, `bs rebuild`, and
  all other commands work identically. The only user-visible
  difference is the JSONL header line, which shrinks from four fields
  to two.

#### What changes for tests

**`test/repository/jsonl_expect.ml`** (5 tests):

- *Round-trip test*: Remove `entity_count` and `hash match`
  assertions from the output. `write` returns unit, so the `hash`
  binding changes to `let () = _unwrap (Jsonl.write ...)`.
- *Content hash determinism test*: Replace the entity-only hash
  comparison with a whole-file hash comparison:
  `Digest.file tmp1 |> Digest.to_hex` vs `Digest.file tmp2 |>
  Digest.to_hex`. Two writes with the same entities and namespace
  produce identical files, so the test still passes.
- *`read_header` test*: Remove entirely (function no longer exists).
- *Empty entities test*: Remove `entity_count` assertion; verify
  `records=0` only.
- *Parse error on invalid type*: Update the hardcoded header string
  to `{"_kbases":"1","namespace":"kb"}` (remove `entity_count` and
  `content_hash`).
- *Parse error on missing header*: Change from `Jsonl.read_header`
  to `Jsonl.read` (both detect "empty file, no header line").

**`test/service/sync_service_expect.ml`** (6 tests):

- *Flush writes JSONL file*: Remove `entity_count` from the
  assertion. The test reads the written file and verifies
  `record_count` and `namespace`, which still work.
- *Flush updates content hash*: No structural change — the test
  verifies that the hash in config changes after adding an entity
  and re-flushing. The hash is now a whole-file hash but the test
  logic is the same.
- *Force rebuild*: No change — the test verifies entity
  reimporting, which is unaffected.
- *Rebuild detects hash mismatch*: No change to test logic. The
  test writes a JSONL file externally (via `Jsonl.write`), then
  calls `rebuild_if_needed`. The whole-file hash of the externally
  written file won't match the stored hash, triggering a rebuild
  as before.
- *Rebuild no-ops when hashes match*: No change — flush stores the
  hash, rebuild reads the same file and gets the same hash.
- *Rebuild no-ops when no JSONL file*: No change.

**`test-perf/perf_harness.ml`**:

- `generate_jsonl` drops the `entity_count` and `content_hash`
  fields from the header `Assoc` list. The `Digest.string
  entity_content` computation (line 65) and the `entity_count`
  binding (line 66) are removed. Entity serialization is unchanged.

#### Limitations

- **`rebuild_if_needed` reads the entire file** to hash it, rather
  than reading just line 1. For a 10,000-entity KB (~1.5 MB file),
  `Digest.file` takes approximately 1–2 ms (MD5 throughput is ~1
  GB/s on modern hardware). The old `read_header` took negligible
  time. The difference is small in absolute terms but represents a
  ~1–2 ms regression on the fast path (no rebuild needed). This is
  acceptable: the fast path currently involves one line read + one
  SQLite query + process startup; the additional 1–2 ms is noise
  within that.

- **Hash algorithm remains MD5.** MD5 is adequate for change
  detection but not cryptographically secure. The hash is used
  solely for detecting file changes, never for security, so this
  is not a concern. If a stronger hash is desired in the future,
  `Digest.BLAKE256.file` (available since OCaml 5.2) is a
  drop-in replacement.

- **Double write on first invocation after flush.** In `flush`, the
  file is written by `Jsonl.write` and then re-read by
  `Digest.file` for hashing. The file is already in the OS page
  cache, so the re-read is a memory copy, not a disk read. An
  alternative would be to hash the `full_content` string inside
  `write` before writing it to disk — but that would require
  `write` to return the hash, contradicting requirement 5. The
  clean separation (write is write, hash is hash) is worth the
  negligible re-read cost.

#### Research needed

None. The one question — `Digest.file` availability in OCaml 5.3 —
was resolved during this invocation by reading
`~/.opam/default/lib/ocaml/digest.mli`. The function is present
(line 68), not deprecated, and consistent with the existing use of
`Digest.string` in the codebase.

## Design Decisions

**1. Whole-file hash over entity-only hash.** The stored hash now
covers the entire file — header, entity lines, and newlines — not
just the concatenated entity content. This is simpler: no parsing is
needed to separate header from content before hashing. It is also
more correct: any change to the file triggers a rebuild, including
future additions to the header (e.g., a new stable field). The
alternative (entity-only hash) would require parsing at least enough
to skip the header line, reintroducing the coupling this design
eliminates. Resolved during requirements refinement (open question 1).

**2. Hash computation at the service layer.** Hashing moves from the
`Jsonl` module (where it was embedded in the write path) to
`Sync_service` (where it is consumed for rebuild detection). This
follows the existing layering: `Jsonl` handles serialization and
deserialization, `Sync_service` handles synchronization logic
including change detection. The alternative — keeping hash awareness
in `Jsonl` — would leave `write` coupled to rebuild detection despite
no longer embedding the hash in the file.

**3. `Digest.file` for runtime hashing.** The OCaml standard library
provides `Digest.file : string -> t`, which reads a file and computes
its MD5 digest in a single call. This is used in preference to
reading the file into a string and calling `Digest.string`, because
`Digest.file` is more direct and the codebase already depends on the
`Digest` module. The function is available and not deprecated in
OCaml 5.3. If a stronger hash is needed in the future,
`Digest.BLAKE256.file` (available since OCaml 5.2) is a drop-in
replacement.

**4. Tolerant parsing over format versioning.** The parser ignores
unknown fields in the header JSON rather than bumping the `_kbases`
version to `"2"`. The change makes the header *simpler* (fewer
fields), not incompatible. A version bump would require old code to
reject new files and new code to handle both versions — unnecessary
complexity for a backwards-compatible simplification. The `_kbases`
field stays at `"1"`.

**5. Accept one-time rebuild on upgrade.** The first invocation after
upgrading will always trigger a rebuild: the stored hash (entity-only
MD5 from the old code) will never match the new whole-file MD5. This
is accepted rather than adding migration logic. The rebuild is
self-correcting (it rewrites the file in the new format and stores
the new hash), costs the same as any other rebuild, and happens
exactly once.

## Rejected Alternatives

**Fixed placeholder values.** Replace `entity_count` and
`content_hash` with stable placeholders (`0` and `"none"`) so the
header line doesn't change across flushes. Rejected: a field named
`content_hash` that is always `"none"` is actively misleading.
Keeping fields around with dummy values adds no value over removing
them and creates a maintenance trap where someone might try to use
them. Does not satisfy requirements 1 or 2.

**In-write hash of full content.** Have `Jsonl.write` compute
`Digest.string full_content` from the bytes already assembled in
memory, returning the hash to the caller. This avoids the post-write
re-read in `flush`. Rejected: contradicts requirement 5 (`write`
returns unit) and keeps the write path coupled to rebuild detection.
The post-write re-read is negligible — the file is in the OS page
cache, making `Digest.file` a memory copy rather than a disk read.

**Retain `read_header` without callers.** Keep the function for
hypothetical future use. Rejected: contradicts requirement 6. Dead
code is maintenance burden, and the function is trivial to
reintroduce if needed.

**Eliminate the header line entirely.** With only `_kbases` and
`namespace` remaining, move them elsewhere (filename convention,
config file) and make the JSONL file pure entity data. Rejected: the
header serves as a format identifier (`_kbases` distinguishes a
knowledge-base JSONL from arbitrary JSONL) and carries the namespace
without requiring path-based inference. Two stable fields earn their
place in the file.

## Consequences and Trade-offs

**Merge behavior.** The motivating concern. Today, every pair of
branches that independently run any write command produces a
guaranteed merge conflict on line 1. After this change, line 1 is
identical across all branches within a repository (same `_kbases`,
same `namespace`), so git sees no conflict. Entity lines already
merge cleanly due to TypeId-based sorting. The JSONL file becomes
fully auto-mergeable for the common case of independent additions —
the design intent of the format is finally realized.

**Fast-path performance.** `rebuild_if_needed` currently reads one
line and parses one JSON object (~microseconds). After this change,
it hashes the entire file via `Digest.file` (~1–2 ms for a 10,000-
entity KB). This is a measurable regression in relative terms but
negligible in absolute terms: the fast path also includes process
startup, SQLite connection, and a config query, all of which dwarf
1–2 ms. The performance test harness can verify this if needed.

**Simplicity.** The change is a net simplification. The `Jsonl`
module loses ~15 lines (hash computation, `entity_count` binding,
`read_header` function, two record fields) and gains nothing. The
`Sync_service` gains ~3 lines (the `_hash_file` helper) but loses
the `header.Jsonl.content_hash` coupling. The header type shrinks
from four fields to two. The `.mli` loses one exported function.
Total: fewer lines, fewer concepts, cleaner module boundaries.

**Type safety.** Removing `entity_count` and `content_hash` from the
`header` record type causes compile errors at every site that
accesses them. This is a strength: the compiler enforces completeness
of the change. No field is silently ignored or accidentally left
referencing a removed concept.

**Migration path.** The change is atomic in the sense that all code
changes can land in a single commit. There is no intermediate state
where old and new code must coexist in the same binary. Old-format
files are handled by tolerant parsing (requirement 7). The one-time
rebuild on upgrade is automatic and transparent. No manual migration
step is needed.

**Adding a new stable header field in the future.** If the header
gains a new field (e.g., a schema version for entity format), it
would be added to `_header_to_json` and `_parse_header_json`. The
whole-file hash would automatically detect the change on upgrade
(triggering a rebuild), just as it does for the current format
transition. No special handling needed — this is a benefit of
whole-file hashing.

## Requirement Coverage

| # | Requirement | How satisfied |
|---|-------------|---------------|
| 1 | Remove `entity_count` from header | `entity_count` is removed from the `header` type, `_header_to_json`, and `_parse_header_json`. No longer written to the file. Parser ignores it if present in old files. |
| 2 | Remove `content_hash` from header | `content_hash` is removed from the `header` type, `_header_to_json`, and `_parse_header_json`. No longer written to the file. Parser ignores it if present in old files. |
| 3 | Preserve rebuild detection via whole-file hash | `Sync_service._hash_file` uses `Digest.file` to hash the entire file at the three required points: `rebuild_if_needed` (compare), `flush` (store after write), `force_rebuild` (store after read). Hash stored in SQLite config under the existing `content_hash` key. |
| 4 | Header contains only stable fields | Header becomes `{"_kbases":"1","namespace":"kb"}` — both fields are set at `bs init` and never change. Identical across all branches within a repository. |
| 5 | `Jsonl.write` returns unit | `write` signature changes to `(unit, error) result`. Hash computation removed from the function body. Caller (`flush`) hashes independently after write. |
| 6 | Remove `Jsonl.read_header` | Function deleted from `jsonl.ml` and `jsonl.mli`. Its sole caller (`rebuild_if_needed`) replaced with `_hash_file`. |
| 7 | Parser handles old-format headers | `_parse_header_json` reads only `_kbases` and `namespace`, ignoring any additional fields. Old headers with `entity_count` and `content_hash` parse without error. |
| 8 | Update product requirements | The JSONL design considerations section of `docs/product-requirements.md` is updated to document the stable-header-only rule and the whole-file hash rebuild mechanism. *(Implementation task — not a code change within the approach, but called out as a requirement.)* |

## Recommendation

**Approach A: Whole-file hash at the service layer.**

There is one approach because the requirements are prescriptive
enough to determine the design. This is not a limitation — it
reflects that the problem analysis (background, observations, open
questions) was thorough enough to resolve design choices before the
approach phase rather than during it. The approach satisfies all
eight requirements, introduces no new dependencies, and is a net
simplification of the codebase.

The change eliminates the only source of merge conflicts in normal
JSONL operation, completing the auto-merge story that the sorted
entity format was designed to enable. The trade-off — a ~1–2 ms
regression on the rebuild-detection fast path — is negligible in
context and justified by the simplification of both the file format
and the module architecture.

No fallback is needed: the approach is low-risk (type-safe removal
of fields, well-tested code paths, one-to-one replacement of hash
mechanism) and fully reversible if an unforeseen issue arises. No
more invasive future step is anticipated — the header format after
this change is minimal and stable.
