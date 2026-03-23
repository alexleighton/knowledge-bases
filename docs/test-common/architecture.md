# `test-common/` Architecture

Shared test utilities used by both `test/` and `test-integration/`.

## Purpose

`test-common/` owns helpers that are needed by more than one test library.
Before this directory existed, `test/service/test_helpers.ml` and
`test-integration/test_helper.ml` each carried their own copies of
filesystem and database helpers. `test-common/` is the single source of
truth for that shared logic.

## What belongs here

* **Filesystem helpers** — `rm_rf`, `create_git_root`, `with_git_root`,
  `with_temp_dir`. These bracket test bodies with deterministic cleanup.
* **Database query helpers** — `query_db`, `query_rows`, `query_count`
  (and their `_raw` variants that accept a bare `Sqlite3.db` handle).
  Used by unit tests to assert on persisted state.

## What does not belong here

* **Integration-test infrastructure** — subprocess execution, output
  normalisation, and anything that depends on the compiled `bs` binary.
  These stay in `test-integration/test_helper.ml`.
* **Test-specific setup** — helpers that wrap a particular service
  (`with_query_service`, `with_mutation_service`) belong in their
  respective `test/` subdirectory's `test_helpers.ml`.

## Library name and usage

The dune library is `kbases_tests_common`. It is `(wrapped false)` so
consumer code references modules directly (e.g., `Test_common.with_git_root`).

To use it, add `kbases_tests_common` to the `(libraries …)` list in the
consumer's dune file:

```dune
(library
 (name kbases_tests_service)
 (inline_tests)
 (libraries kbases kbases_tests_common)
 (preprocess (pps ppx_inline_test ppx_expect))
)
```

## File layout

```
test-common/
  dune              — library definition
  test_common.ml    — all shared helpers (single module)
```

When the module outgrows ~300 lines, split by concern (e.g.,
`test_fs.ml` for filesystem helpers, `test_db.ml` for query helpers).
