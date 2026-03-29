# Common Helper Usage

Scan code for places where existing common helpers could replace
hand-written logic. This is a maintenance task — the goal is to
reduce duplication by using helpers the project already provides,
not to create new abstractions.

## Scope

The user will specify a directory to review (e.g., `lib/service/`,
`lib/`, `bin/`). All `.ml` and `.mli` files in the specified
directory are in scope.

## Process

### 1. Inventory common helpers

Read the shared utility modules that the scoped code depends on.
Build a complete inventory — the following are examples, not an
exhaustive list:

* **`Data.Result`** — `sequence`, `traverse`, and `Syntax` operators
  (`let*`, `let+`).
* **`Data.String`** — `contains_substring`, `rsplit`.
* **`Data.Char`** — `is_lowercase`, `is_digit`, `is_hex_digit`, etc.
* **`Control.Assert`** — `require`, `requiref`, `require_strlen`.
* **`Control.Io`** — `read_file`, `write_file`, `read_all_stdin`.
* **Domain-type operations** — `equal`, `compare`, `parse`, `pp`,
  `show`, and any other operations exposed by Data modules
  (e.g., `Relation_kind.equal`, `Timestamp.compare`).

Any shared module the scoped code opens or depends on is fair game.

Also look at within-scope helpers: shared error mappers, wrapper
functions, or utilities defined in one module that other modules in
the same scope could (but don't) use.

Read every helper's signature and understand what it does. The
inventory is the lens through which you will read the rest of the
code.

### 2. Scan for missed usage opportunities

Read every `.ml` file in scope. For each file, look for code that
reimplements logic a common helper already provides. Common
patterns:

* **Manual recursive traversal** of a list with a fallible function
  — replaceable by `Data.Result.traverse` or `Data.Result.sequence`.
* **Inline error mapping** that duplicates a named mapper already
  defined in the same file or a dependency.
* **Primitive operations on abstract types** — converting a domain
  value to its underlying representation (e.g., `to_string`) in
  order to perform an operation the type already exposes (e.g.,
  comparing two `Relation_kind.t` values via their string
  representations instead of using `Relation_kind.equal`).
* **Reimplemented control flow** — hand-rolled `try`/`with` or
  `match Ok/Error` chains where `Result.Syntax` operators or
  `Result.map_error` would flatten the code.
* **Duplicated validation** — inline length checks or format checks
  that a `Control.Assert` function or a Data smart constructor
  already performs.

### 3. Classify findings

For each finding, determine which category it falls into:

* **Direct replacement** — the helper's signature already fits the
  call site. The fix is a drop-in substitution with no changes to
  the helper.
* **Helper adjustment needed** — the helper almost fits but needs a
  small API change (e.g., an additional parameter, a relaxed type).
  Present the proposed change so the user can decide — do not widen
  or narrow a helper's API without approval.

Discard any finding where you cannot propose a specific replacement.
"This code could maybe use X" is not a finding.

### 4. Present findings

Produce a numbered list. For each finding:

* **State what you found and where** — file, line range, and the
  code pattern.
* **Name the helper that should be used** — module and function.
  Verify that the helper is semantically equivalent to the
  hand-written code, not just signature-compatible.
* **Show the replacement** — a before/after code block for the
  call site. For direct replacements, this is the fix. For
  helper-adjustment findings, also show the helper change.
* **Mark the category** — direct replacement or helper adjustment
  needed.

### 5. Act on decisions

The user will accept or reject each finding. When implementing
accepted changes:

* Apply all changes in a single editing pass.
* Run `dune build`, `dune runtest`, and `dune build @runcheck`
  after all changes. All three must pass.
* If a helper adjustment was accepted, update the helper, its
  `.mli` signature if one exists, all existing callers, and its
  tests before using it at the new call site.
