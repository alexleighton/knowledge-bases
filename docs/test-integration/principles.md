# `test-integration/` Principles

Guiding principles for code that lives in `test-integration/`.

## 1. Low nesting depth

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
  structure repeats across call sites or tests — e.g., acquire a resource,
  match on the result, use it, clean up — give that shape a name.

* **Unwrap setup results that must succeed.** When a test setup step (e.g.,
  initialising a repository) is expected to always succeed, use an unwrap
  helper that fails on error rather than nesting the entire test body inside
  a `match` arm.
