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

## 4. Low nesting depth

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

## 5. Parameterize shared helpers

When a shared helper hardcodes a behavioral choice — an exit code, an output
destination, an error-mapping strategy — callers that need a different value are
forced to bypass the helper entirely, duplicating its other responsibilities.

Make the varying choice a parameter with a sensible default so existing callers
don't change and new callers can override just the part that differs.

**Example:** `exit_with` hardcodes `exit 1`. A command that needs exit code 123
for a specific failure mode must bypass `exit_with` and duplicate the
stderr-formatting logic. Adding `?(code = 1)` solves this — existing callers
are unchanged.

## 6. Every subcommand supports `--json`

All subcommands that produce output must accept a `--json` flag. When
passed, the command prints a single JSON object (or array, for `list`)
to stdout instead of human-readable text.

Use the shared `Common.json_flag` defined in `cmdline_common.ml` and
thread it into the command's `Term`. Use `Common.print_json` to emit
the result.

### JSON shape conventions

- The top-level object includes `"ok": true` on success.
- Keys use `snake_case`.
- Errors **are** JSON-formatted when `--json` is passed: the command
  prints `{"ok": false, "reason": "…", "message": "…"}` to stdout and
  exits non-zero. Use `Common.exit_with_error ~json` to get this
  behaviour. Without `--json`, errors go to stderr as plain text.
- Each command's JSON serialization lives inline in its `cmd_*.ml`
  file. The shapes are a presentation concern and intentionally
  separate from the JSONL persistence format in `lib/`.

When adding a new subcommand, include `--json` support from the start
and add at least one `--json` integration test in the command's
`test-integration/<command>_expect.ml` file.

## 7. File length

Keep files below approximately 300 lines. Larger files are harder to read and
understand. A file approaching this limit is often a sign that the concept it
represents is too complex and should be broken into smaller, composable
pieces.

## 8. Help text and examples

Every subcommand must have:

- An **EXAMPLES** section demonstrating every flag and common flag
  combinations. Each example should be preceded by a short annotation
  explaining *when* or *why* you would use it, not just restating the
  command (e.g., `"List only todos you can start working on:"` rather than
  `"Use the available flag:"`).
- A **`--json` example** in every subcommand's EXAMPLES section, even simple
  ones like `resolve` or `archive`. Agents and scripts rely on JSON output
  and won't discover it without an example.
- A **`--show` example** for any command that supports it (e.g., `claim`,
  `next`), showing that it can be combined with `--json`.
- A **semantic `~doc` string** for every flag. The description should explain
  what the flag *does* and *when* to use it, not just restate its name. For
  relation flags, mention directionality and how the relation appears in
  `show` output.
- **Constraint documentation** in `~doc` strings: when a flag has
  interactions or restrictions with other flags (e.g., `--available` cannot
  be combined with `--status`), state that in the flag's `~doc`.

When adding a new command or flag, include corresponding help text updates in
the same change. The root `bs --help` should include a lifecycle example that
walks through init, create, query, claim, complete, and sync.

## 9. Command ordering in `Cmd.group`

Commands in the `Cmd.group` list in `main.ml` are ordered by domain group, not
alphabetically or by addition date. Related commands appear adjacent to each
other. The current groups, in order:

1. **Lifecycle** — `init`, `uninstall`
2. **Create** — `add note`, `add todo`
3. **Query** — `list`, `show`
4. **Workflow** — `update`, `claim`, `next`, `resolve`, `close`, `archive`,
   `reopen`, `delete`
5. **Relations** — `relate`, `unrelate`
6. **Sync & maintenance** — `flush`, `rebuild`, `gc`

When adding a new command, place it in the appropriate group rather than
appending to the end.

Note: the root `bs --help` COMMANDS section is auto-generated by Cmdliner in
alphabetical order. The `Cmd.group` ordering does not affect help output but
keeps the source readable.
