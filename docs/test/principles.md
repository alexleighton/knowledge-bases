# Test Principles

Guiding principles for writing and organising tests in this project.

## 1. Mirror the source tree

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
