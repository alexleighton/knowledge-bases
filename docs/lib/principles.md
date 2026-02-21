# `lib/` Principles

Guiding principles for code that lives in `lib/`.

## 1. No duplication

Do not duplicate or near-duplicate code across modules. When the same logic
appears in two places, one of two things is true:

1. **The code needs to be refactored for visibility.** The shared logic already
   exists but is hidden — locked behind a private helper, buried in the wrong
   layer, or scoped too narrowly. The fix is to extract it into a module (or
   promote it in an `.mli`) so both call sites can reach it.

2. **There is a missing abstraction.** The repeated code is a signal that a
   concept exists in the domain but has not been named yet. Introduce the
   abstraction — a new function, type, or module — that captures the common
   pattern in one place.

   A particularly important case: **duplicated validation means a missing
   type.** When two modules validate the same constraint on a raw value
   (e.g., "string must be 1–100 characters"), the constrained value space is
   a concept that deserves its own Data module. Give it an abstract type and
   a smart constructor that enforces the invariant once. Both modules then
   accept the validated type instead of the raw value, and the duplicate
   validators disappear.

**Why:** Duplicated code is a maintenance liability. When the logic changes,
every copy must be found and updated in lockstep. Worse, near-duplicates
diverge silently over time, producing subtle inconsistencies that are hard to
diagnose. A single source of truth is easier to test, easier to reason about,
and cheaper to evolve.

## 2. Correct Construction

When modeling domain types and value objects, follow the Correct Construction
pattern: validate on construction, keep values immutable, and encapsulate
primitives. See [Correct Construction](correct-construction.md) for the full
treatment.

## 3. Low nesting depth

Keep expressions nested at most two or three levels deep. Deeply nested code
is hard to follow because the reader must hold every enclosing context in their
head at once. When nesting grows, treat it as a signal that the code should be
restructured.

Approaches for reducing nesting:

* **Use monadic result operators (`let*`, `let+`).** Replace manual
  `match … with Ok x -> … | Error e -> Error e` chains with `Result.Syntax`
  bind operators so each step in a result pipeline sits at the same
  indentation level.

* **Extract resource-management wrappers.** When code follows a
  setup/use/cleanup pattern (transactions, file handles, temporary state),
  capture the bracketing in a higher-order function that takes the body as a
  callback.

* **Consolidate error mapping into named functions.** Instead of matching on
  error variants inline at every call site, define a reusable mapping function
  and apply it with `Result.map_error` in a pipeline.

* **Factor repeated control-flow shapes into helpers.** When the same nesting
  structure repeats across call sites — e.g., acquire a resource, match on the
  result, use it, clean up — give that shape a name.

* **Catch exceptions in low-level wrappers.** When a module wraps an external
  library that raises, catch exceptions internally and return result values.
  This removes `try`/`with` nesting from every call site.

## 4. File length

Keep files below approximately 300 lines. Larger files are harder to read and
understand. A file approaching this limit is often a sign that the concept it
represents is too complex and should be broken into smaller, composable
modules.
