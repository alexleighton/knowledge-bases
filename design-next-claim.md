# Design: `next` and `claim` commands

## Problem Statement

An agent (or developer) using `bs` to track work currently has no direct way
to pick up the next piece of work. The workflow today is:

1. `bs list todo --status open` to see what's available.
2. Manually inspect dependencies (via `bs show`) to determine which todos are
   not blocked.
3. `bs update kb-N --status in-progress` to claim one.

This is tedious for humans and error-prone for agents, which must parse list
output, reason about dependency graphs, and issue a separate update. The
knowledge base already has the information needed to answer "what should I work
on next?" — open todos, `depends-on` relations, and todo statuses — but no
command exposes that reasoning.

Two commands are needed: one that automatically selects the best available todo
(`next`), and one that claims a specific todo the caller has already chosen
(`claim`). Both transition the selected todo to `in-progress`.

Additionally, the `depends-on` relation has a semantic consequence — it can
block a todo — but this is invisible in the current `show` output. When an
agent looks at a todo's relations, nothing indicates whether a dependency is
satisfied or still outstanding.

## Requirements (first pass)

1. **`next` selects an available todo.** `bs next` picks the first open todo
   (by niceid order) that has no unresolved dependencies, transitions it to
   `in-progress`, and outputs a confirmation. "Unresolved" means the
   `depends-on` target is a todo whose status is not `done`. — *Rationale:
   niceid order is deterministic and matches the user's mental model of the
   list; dependency resolution uses the existing `depends-on` semantics.*

2. **`claim` transitions a specific todo.** `bs claim IDENTIFIER` takes a
   niceid or TypeId, validates that the target is an open, unblocked todo, and
   transitions it to `in-progress`. — *Rationale: agents sometimes know which
   todo they want; `claim` skips the selection step while enforcing the same
   guards.*

3. **Default output is a confirmation line.** Both commands print
   `Claimed todo: <niceid>  <title>` on success. — *Rationale: minimal,
   informative output suitable for both humans glancing at a terminal and
   agents parsing a known format.*

4. **`--show` flag displays full item details.** When passed, both commands
   print the same output as `bs show` for the claimed todo (including
   relations) instead of the one-liner. — *Rationale: lets the agent
   immediately see the todo's content and context without a follow-up
   `bs show` call.*

5. **Distinguished error types.** Errors are not generic strings. Each failure
   mode has its own variant so callers (especially agents using `--json`) can
   distinguish between "not a todo", "not open", "blocked by dependencies",
   and "nothing available". — *Rationale: agents need to branch on failure
   reasons, not parse error messages.*

   | Condition                        | Applies to | Error             |
   |----------------------------------|------------|-------------------|
   | Target is a note, not a todo     | `claim`    | `Not_a_todo`      |
   | Todo status is not `open`        | `claim`    | `Not_open`        |
   | Todo has unresolved dependencies | `claim`    | `Blocked`         |
   | No open unblocked todos exist    | `next`     | `Nothing_available` |

6. **Blocking annotation on relation display.** Whenever relations are
   displayed (currently only `show`), any `depends-on` relation whose target
   is a non-`done` todo is annotated as blocking. In human-readable output
   this appears as a `[blocking]` tag; in JSON output as a boolean field. —
   *Rationale: makes dependency status visible at the point where the user is
   already looking at relations, without requiring a separate query.*

7. **`--json` support.** Both `next` and `claim` support `--json`, consistent
   with every other `bs` command. JSON error output includes a machine-readable
   reason key. — *Rationale: standard `bs` convention; agents depend on it.*

## Scenarios

### Scenario 1: Agent picks up work with `next`

Starting state: three open todos. `kb-1` depends on `kb-2` (which is open).
`kb-0` has no dependencies.

```
$ bs list todo --status open
kb-0  todo  open  Write unit tests for parser
kb-1  todo  open  Refactor parser module
kb-2  todo  open  Define error types
```

Agent runs:

```
$ bs next
Claimed todo: kb-0  Write unit tests for parser
```

`kb-0` was selected because it is the first (by niceid) open todo with no
unresolved dependencies. `kb-1` was skipped because it depends on `kb-2`,
which is not done.

```
$ bs show kb-0
todo kb-0 (todo_01abc...)
Status: in-progress
Title:  Write unit tests for parser

Add tests for the tokenizer edge cases.
```

### Scenario 2: Agent claims a specific todo

```
$ bs claim kb-2
Claimed todo: kb-2  Define error types
```

The agent chose `kb-2` directly. It was open and unblocked, so the claim
succeeded.

### Scenario 3: Claiming a blocked todo

`kb-1` depends on `kb-2`, which is still open.

```
$ bs claim kb-1
Error: kb-1 is blocked by: kb-2
```

With `--json`:

```json
{"ok":false,"reason":"blocked","niceid":"kb-1","blocked_by":["kb-2"]}
```

### Scenario 4: Claiming a non-open todo

```
$ bs claim kb-0
Error: kb-0 is already in-progress
```

### Scenario 5: No available work

All open todos are blocked, or there are no open todos.

```
$ bs next
Error: no open unblocked todos
```

### Scenario 6: `--show` flag

```
$ bs next --show
todo kb-2 (todo_01def...)
Status: in-progress
Title:  Define error types

Create a structured error type hierarchy for the parser.

Incoming:
  depends-on  kb-1  todo  Refactor parser module  [blocking]
```

The `[blocking]` tag on the incoming `depends-on` from `kb-1` indicates that
`kb-1` is not yet done and is therefore still blocked by this todo.

### Scenario 7: Blocking annotation in `show`

```
$ bs show kb-1
todo kb-1 (todo_01ghi...)
Status: open
Title:  Refactor parser module

Restructure the parser to use the new error types.

Outgoing:
  depends-on  kb-2  todo  Define error types  [blocking]
  related-to  kb-5  note  Parser design notes
```

The `[blocking]` tag appears on the `depends-on` to `kb-2` because `kb-2` is
not done. The `related-to` has no blocking annotation (it is not a
`depends-on` relation).

After `kb-2` is resolved:

```
$ bs resolve kb-2
$ bs show kb-1
...
Outgoing:
  depends-on  kb-2  todo  Define error types
  related-to  kb-5  note  Parser design notes
```

The `[blocking]` tag disappears because `kb-2` is now done.

## Constraints

- Existing CLI commands must continue to work identically. `next` and `claim`
  are additive.
- The on-disk formats (JSONL and SQLite schema) must not change. No new tables
  or fields are needed — blocking is computed from existing `depends-on`
  relations and todo statuses.
- No new runtime dependencies.
- `next` selection must be deterministic given the same knowledge base state.
- Both commands are non-interactive, consistent with the existing `bs`
  constraint that all input comes from arguments and stdin.

## Open Questions

None — all design points resolved in discussion.
