# Documentation Upkeep

Audit the project's documentation for staleness and correct any
problems found. This is a maintenance task, not a creative one — the
goal is to make the existing docs accurate, not to write new ones.

## Scope

The documentation lives in `docs/`, indexed by `docs/index.md`. The
index is the entry point: every document under `docs/` must appear in
it, and every entry in the index must point to a file that exists.

**Exception:** `docs/designs/` contains historical design documents
that capture the reasoning behind past decisions. They are not kept up
to date and should not be checked for staleness or individually
indexed. The index covers them with a single wildcard entry.

## Process

### 1. Verify the index is complete and accurate

Compare the entries in `docs/index.md` against the actual files on
disk.

* **Missing entries** — a file exists under `docs/` but is not listed
  in the index. Add it with a one-line description matching the style
  of the existing entries.
* **Stale entries** — the index lists a file that no longer exists, or
  the description no longer matches the document's content. Fix or
  remove the entry.

The index is sorted by path. Preserve this ordering when adding
entries.

### 2. Check each document for staleness

Read every document the index references. For each one, look for
claims that contradict the current state of the code. Common sources
of staleness:

* **Example tables** — architecture docs list example modules in
  tables. A listed module may have been renamed, removed, or moved to
  a different layer. An important new module may be absent. Update the
  table to reflect reality, but do not exhaustively list every module
  — tables are illustrative, not inventories.
* **Backlog documents** — files like `deferred-tests.md` describe
  work that is blocked on missing functionality. If the blocking
  functionality has since landed, the backlog entry is stale. Either
  remove the entry (if the deferred work has been done) or flag it for
  the user to act on.
* **Stated constraints that no longer hold** — a principle or
  architecture doc may say "the CLI does not support X" as context for
  a design decision. If X now exists, the surrounding text may need
  adjustment.
* **Renamed concepts** — if a type, module, or command has been
  renamed, references in prose should be updated to match.

### 3. Fixes only, not rewrites

Change only what is wrong. Do not restructure documents, rewrite
sections for style, or add material beyond what is needed to restore
accuracy. If a document has a deeper structural problem (e.g., it
describes an architecture that has been fundamentally reorganised),
flag it to the user rather than attempting a large rewrite.

### 4. Report what you found

After making corrections, summarise:

* Which index entries were added, removed, or updated.
* Which documents had stale content and what was corrected.
* Any documents that need attention beyond simple fixes.
