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
