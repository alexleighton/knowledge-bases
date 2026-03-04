# Test Principles

Guiding principles for writing and organising tests in this project.

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

## 2. Mirror the source tree

Test files should live under a directory structure that mirrors `lib/`. A test
exercising code from `lib/service/` belongs in `test/service/`, not at the top
level of `test/`.

Each subdirectory needs its own `dune` file declaring a library so that dune
discovers and runs the tests. Follow the existing pattern:

```dune
(include_subdirs no)

(library
 (name kbases_tests_<subdir>)
 (inline_tests)
 (libraries kbases)
 (preprocess (pps ppx_inline_test ppx_expect))
)
```

**Why:** Keeping the test layout parallel to the source layout makes it easy to
locate the tests for any given module. It also keeps dune libraries focused and
avoids a single catch-all test library that grows without bound.

## 3. Assert on state, not just return values

When a unit test exercises code that produces side effects — writing to a
database, creating files, allocating IDs — the test should verify the
**persisted state**, not only the value returned by the function under test.

A test that calls a service method and inspects only the returned domain object
is doing the same work as an integration test that calls the CLI and inspects
stdout. Both confirm "given these inputs, the output looks like X." Neither
confirms that the side effect actually happened correctly.

To make unit tests earn their keep:

* **Query the database directly.** After calling a service or repository
  method, run a small SQL query against the in-memory database to verify the
  expected rows exist with the correct column values. Use the `query_db` test
  helper for this.

* **Check absence as well as presence.** Verify that no unexpected rows were
  created (e.g., `SELECT count(*) FROM todo` returns exactly the expected
  count), not just that the right row is there.

* **Reserve return-value assertions for error mapping and shaping.** When the
  function under test returns a validation error or maps a repository error into
  a service error, a return-value assertion is the right tool — there is no
  database state to inspect. The rule of thumb: if the test exercises a code
  path that writes nothing, assert on the return value; if it exercises a code
  path that writes something, assert on what was written.

**Why:** Unit tests that only check return values are redundant with integration
tests. State-based assertions catch bugs that return-value tests cannot — for
instance, a service that returns a correct object but fails to persist it, or
persists extra or incorrect data. This gives each test layer a distinct role:
unit tests verify side effects, integration tests verify end-to-end CLI
behaviour.

## 4. Clean up temporary files and directories

Tests that create temporary files or directories must remove them when the test
finishes — including when the test fails or raises an exception. Use
`Fun.protect ~finally` or a cleanup wrapper to guarantee removal.

* **Prefer `with_git_root` / `with_temp_dir` over `create_git_root` /
  `Filename.temp_dir`.** The `with_*` wrappers in `test_helpers` bracket the
  test body and clean up automatically. Use bare creation functions only when
  the wrapper's callback shape doesn't fit, and pair them with an explicit
  `Fun.protect ~finally` block.

* **Clean up temp files too.** When a test creates individual temp files via
  `Filename.temp_file`, wrap the test body in `Fun.protect ~finally:(fun () ->
  Sys.remove path)`.

**Why:** Leaked temp directories accumulate across test runs and CI builds,
wasting disk space and making it harder to diagnose failures. Deterministic
cleanup keeps the test environment predictable.
