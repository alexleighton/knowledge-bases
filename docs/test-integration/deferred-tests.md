# Deferred Integration Tests

Integration test scenarios we cannot currently implement via the public CLI,
because the required user-facing functionality does not exist yet.

This file is a backlog record: each item should be turned into a task once the
blocking functionality lands.

## Scope

Current focus: `bs list` integration tests in `test-integration/list_expect.ml`.

Most planned list tests are already implemented (happy path, type/status
filters, empty KB, invalid args, and environment errors). The remaining gaps are
cases that require creating non-default statuses through CLI workflows.

## Deferred tests

### 1) Default exclusion of done todos

**Test intent**

Verify that plain `bs list` excludes todos with status `done`.

**Why blocked**

The CLI currently creates todos as `open` and does not expose a command to
transition todo status to `done`.

**Missing functionality**

- A status-transition command for todos (for example, `bs resolve` or
  `bs update todo --status done`), or
- A controlled test-only CLI path to create a done todo.

**When unblocked, add test**

- Setup: init KB, add at least one todo, transition one todo to `done`.
- Assert:
  - `bs list` omits the done todo.
  - `bs list --status done` includes the done todo.

### 2) Listing archived notes

**Test intent**

Verify that note archiving semantics are observable end-to-end:

- `bs list` excludes archived notes by default.
- `bs list --status archived` includes archived notes.

**Why blocked**

The CLI currently creates notes as `active` and does not expose a command to
archive a note.

**Missing functionality**

- A note archive/unarchive command (for example, `bs archive note` or
  `bs update note --status archived`), or
- A controlled test-only CLI path to create an archived note.

**When unblocked, add test**

- Setup: init KB, add at least one note, archive one note.
- Assert:
  - `bs list` omits the archived note.
  - `bs list --status archived` includes the archived note.

## Task templates

Use these templates to create backlog items later.

### Template: implement missing functionality

- Add a CLI workflow for transitioning item status (`todo -> done`,
  `note -> archived`).
- Cover with service and integration tests.

### Template: add deferred integration assertions

- Extend `test-integration/list_expect.ml` with:
  - default exclusion assertions for transitioned items, and
  - explicit `--status done` / `--status archived` positive assertions.
