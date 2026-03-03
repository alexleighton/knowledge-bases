# In-File Code Organization

Review OCaml source files and improve the internal organization of
definitions. This is a maintenance task — the goal is to make files
scannable by grouping related definitions together and establishing
clear landing zones for future additions. Do not rename, split, or
change the behaviour of anything.

## Scope

All `.ml` and `.mli` files under `lib/` and `bin/`. Operate on the
full codebase unless the user specifies a narrower scope (a directory,
a single file, etc.).

## Canonical ordering

### `.ml` files (implementation)

Definitions in an implementation file should follow this order:

1. **Module aliases and opens** — `module M = …`, `open …`
2. **Type definitions** — types, error variants, records
3. **Error mappers** — functions that convert between error types
4. **Internal helpers** — private functions (prefixed with `_`)
5. **Initialization / construction** — `init`, `create`, `make`
6. **Public operations** — grouped by concern, then ordered read →
   write → lifecycle within each group

When a file serves multiple distinct concerns (e.g., serialization and
parsing, or CLI terms and output formatting), related helpers and
public functions should sit together under their concern rather than
being separated by kind. Within each concern the ordering above still
applies.

### `.mli` files (interface)

Interface files need a lighter touch — their structure is already
constrained by what they expose. The ordering:

1. **Module-level doc comment** — `(** … *)` describing the module's
   purpose
2. **Abstract types** — `type t`, opaque handles
3. **Concrete type definitions** — error types, result records, enums
4. **`val` declarations** — grouped by operation category
   (construction, queries, mutations, lifecycle), each with a doc
   comment

Most `.mli` files in the project are already well-organized. Focus
attention on larger interfaces (roughly 100+ lines) where grouping
`val` declarations by category improves scannability.

## Section comments

Use section comments of the form `(* --- Section name --- *)` to mark
group boundaries **only when the grouping is not already obvious from
the code**. Definitions that are clearly related by naming convention
(e.g., a cluster of `get_*` functions, or `_`-prefixed helpers) do
not need a comment restating what the reader can already see.

Section comments earn their keep when:

* A file mixes genuinely different concerns (serialization vs.
  parsing, CLI terms vs. output formatting).
* A file is long enough (~100+ lines) that scrolling loses context.
* The logical grouping is not apparent from function names or types
  alone.

Do not add section comments to small, single-concern files where the
structure is already clear. Visual noise is worse than no markers at
all.

## Process

### 1. Scan for organization issues

Read each file in scope. For each file, assess:

* Are definitions ordered according to the canonical ordering above,
  or are they interleaved (e.g., a helper wedged between two public
  functions, an error mapper at the bottom)?
* Are related definitions adjacent, or has growth scattered them?
* Would section comments clarify boundaries that are not already
  self-evident?

Skip files that are already well-organized — not every file needs
changes.

### 2. Reorder definitions

Move definitions into the canonical order. This is the primary
value of the task. When reordering:

* **Preserve compilation order.** OCaml requires definitions to
  appear before their use (no forward references). After reordering,
  verify that `dune build` still succeeds.
* **Keep tightly coupled definitions together.** A private helper
  that exists solely to support one public function should stay
  immediately above that function, even if the canonical ordering
  would place it elsewhere.
* **Do not change `.mli` declaration order without checking
  callers.** The `.mli` order is the public API's documentation
  order. Reorder only when it materially improves scannability.

### 3. Add section comments where warranted

After reordering, add `(* --- Section name --- *)` comments where
they pass the bar described above. Remove any existing section
comments that have become redundant after reordering made the
structure self-evident.

### 4. Verify

Run:

```
dune build
dune runtest
```

Both must pass cleanly. Reordering definitions can break compilation
order or expose shadowing — catch these before finishing.

### 5. Report what you found

Summarise:

* Which files were reorganized and what was moved.
* Where section comments were added or removed, and why.
* Any files that were already well-organized and left unchanged.
* Any files where deeper structural issues exist (e.g., mixed
  concerns that would benefit from splitting into separate modules)
  — flag these for the user rather than attempting a split.
