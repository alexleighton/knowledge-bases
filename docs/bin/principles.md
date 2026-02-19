# `bin/` Principles

Guiding principles for code that lives in `bin/`.

## 1. No unit tests for `bin/`

Code in `bin/` is **not** unit tested. It should contain only:

- Command-line argument definitions and parsing (Cmdliner terms and commands).
- Thin orchestration that wires CLI inputs to `lib/` services.

Any logic beyond that — validation, resolution, business rules — belongs in
`lib/` where it can be covered by unit tests. If you find yourself wanting to
test something in `bin/`, that is a signal the logic should move into a module
under `lib/`.

## 2. Integration tests for CLI changes

Every change to command-line arguments, subcommands, or user-facing output
**must** be accompanied by integration tests in `test-integration/`. These
tests invoke the `bs` binary as a subprocess and assert on exit codes,
stdout, and stderr. See `docs/test-integration/architecture.md` for the
file layout and shared helper conventions.

Integration tests are the only way to verify that argument parsing, wiring,
and error reporting work end-to-end. Without them, a typo in a Cmdliner
term or a mismatched error path can ship undetected.

When adding or modifying a command:

1. Add a new `test-integration/<command>_expect.ml` file (or extend an
   existing one) covering at least:
   - The happy path with typical arguments.
   - Each error case the user can hit (missing required args, invalid
     values, missing database, etc.).
2. Use the `Test_helper` utilities (`with_git_root`, `run_bs`,
   `print_result`) so tests are self-contained and clean up after
   themselves.
3. Run `dune runtest` and confirm the new tests pass before considering
   the change complete.

## 3. No resolution logic in `bin/`

Code in `bin/` should pass raw CLI inputs to `lib/` and let Service (or lower
layers) handle resolution, derivation, and lookup. When `bin/` code calls into
Control or Repository directly to figure out *what* to pass to a Service
function, that resolution logic has leaked out of `lib/`. The fix is to push it
down: add a Service function that accepts the raw inputs and does the
resolution internally, returning a `result` that `bin/` can handle by printing
an error and exiting.

## 4. File length

Keep files below approximately 300 lines. Larger files are harder to read and
understand. A file approaching this limit is often a sign that the concept it
represents is too complex and should be broken into smaller, composable
pieces.
