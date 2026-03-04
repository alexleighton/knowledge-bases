# `test-integration/` Architecture

How integration tests are organised and where new tests should go.

## Purpose

Integration tests verify the `bs` CLI end-to-end by invoking the compiled
binary as a subprocess and asserting on exit codes, stdout, and stderr.
They exercise argument parsing, command wiring, and error reporting — things
that unit tests in `test/` cannot reach.

See also `docs/bin/principles.md` §2, which establishes the obligation on
`bin/` code to be accompanied by integration tests.

## File naming

Each CLI command gets its own expect-test file named after the full command
path:

```
test-integration/<command>_expect.ml
```

For nested subcommands, join the path segments with underscores:

| Command       | Test file              |
|---------------|------------------------|
| `bs init`     | `init_expect.ml`       |
| `bs add note` | `add_note_expect.ml`   |
| `bs add todo` | `add_todo_expect.ml`   |

When adding a new CLI command, create a new file following this convention.
When modifying an existing command's behaviour or output, extend the
corresponding file.

**Exception:** `workflow_expect.ml` contains cross-command scenario tests that
chain many operations within a single knowledge base, simulating natural usage.
These tests do not map to a single command and intentionally cut across the
per-command boundary. Each scenario should read like a realistic session — seed
data, build relationships, progress through statuses, query results. Taken
together, the workflow tests should exercise every CLI command at least once.
When adding a new command, extend an existing workflow or add a new one so the
command appears in a lifelike context, not only in its isolated command file.

**Per-command feature tests belong in the command file.** When a feature applies
to many commands (e.g., `--json` output), each command's test for that feature
lives in the command's own `*_expect.ml` file, not in a cross-cutting feature
file. Organising by command keeps the architecture consistent and makes it easy
to see full coverage for any given command in one place.

## Shared test helper

`test_helper.ml` provides the infrastructure all integration tests share:

| Function        | Purpose                                                      |
|-----------------|--------------------------------------------------------------|
| `with_git_root` | Creates a temporary directory with `.git/`, cleans up after  |
| `with_temp_dir` | Creates a plain temporary directory, cleans up after         |
| `run_bs`        | Invokes the `bs` binary with arguments and optional stdin    |
| `print_result`  | Prints exit code, stdout, and stderr with deterministic output |
| `init_kb`       | Initialises a knowledge base in a directory (setup for command tests) |
| `delete_db`     | Removes `.kbases.db` from a directory (setup for auto-rebuild tests) |

`print_result` normalises output so that expect tests are deterministic:
absolute temp-directory paths become `<DIR>` and TypeIds become `<TYPEID>`.

## What each command file should cover

At a minimum:

1. **Happy path** — the command succeeds with typical arguments.
2. **Error cases** — every error the user can hit (missing required args,
   invalid values, missing database, etc.).
3. **Auto-rebuild** — delete `.kbases.db` (leaving only `.kbases.jsonl`), run
   the command, and assert that it succeeds. This verifies that the transparent
   rebuild path in `open_kb` works for each command.

## Build configuration

The dune file declares a single library that discovers all `*_expect.ml`
files. The `(deps %{bin:bs})` stanza ensures the binary is built before
tests run:

```dune
(library
 (name kbases_integration_tests)
 (inline_tests
  (deps %{bin:bs}))
 (libraries kbases unix str)
 (preprocess (pps ppx_inline_test ppx_expect)))
```
