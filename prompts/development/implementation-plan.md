# Implementation Plan

Produce a plan for a code change, stored in `bs`. The plan is a
thinking tool — a place to lay out the shape of a change before
writing code.

## Inputs

The user will give you:

1. **The change** they want to make, described in domain terms. They
   will typically point at the files where the change starts.
2. **The motivation** — why the change matters.

## Process

### 1. Analyse the codebase

Before writing anything, explore broadly. The user told you where the
change starts, not where it ends. Trace outward from the starting files:

* Who calls into these modules? Who depends on their types?
* What tests exist? What do they cover?
* What documentation or principles govern how this code is organised?

The goal is to produce an accurate **impact analysis** — the set of
files that will need to change — so the tasks you write later are
grounded in reality, not guesswork.

### 2. Create the plan note

Create a `bs` note whose title is the name of the change (e.g.,
`"Plan: add X"`). The body should contain these sections, in order:

* **Required reading** — list every `docs/` file relevant to the
  change (use `docs/index.md` to find them). The implementer must
  read these before starting work.
* **Goal** — one paragraph restating the change and why it matters.
* **Current state** — a concise sketch of the relevant types,
  signatures, or architecture as they stand today. Code snippets are
  fine. The reader should be able to understand what exists without
  opening a file.
* **Target state** — the same sketch, after the change. Make the
  difference from "current state" visually obvious.
* **Impact analysis** — a table or list of every file that needs to
  change, grouped by layer or area. Call out files that do *not* need
  to change when this is surprising or worth confirming.
* **Design decisions** — anything that requires a judgment call. Name
  the decision, explain the options considered, and state which one the
  plan takes and why. Do not bury design decisions inside task
  descriptions.
* **Atomic groups** — any tasks that cannot be split into
  independently-compilable steps (e.g., changing an interface, its
  tests, and its implementation). Name each group and explain why those
  tasks must land together. Tasks not in a group can be delivered
  independently.

```
echo "<body>" | bs add note "Plan: add X"
```

### 3. Create task todos

Create one `bs` todo per task. Each todo title should be short and
imperative (e.g., `"Update Foo.t and callers"`). The body should
contain:

* **Files** — which files are created or changed.
* **Description** — what to do, concretely. Enumerate the key changes.
* **TDD note** — how test-driven development applies to this task.

Tasks should be ordered so that each one moves the codebase from one
valid state to the next where possible.

```
echo "<body>" | bs add todo "Task title"
```

### 4. Relate tasks to the plan and to each other

Link every task todo back to the plan note:

```
bs relate todo-X --related-to kb-N
```

Encode the dependency graph using `--depends-on`:

```
bs relate todo-X --depends-on todo-Y
```

This relation replaces the "Depends on" field you might otherwise
write inside a task body. The dependency graph *is* the execution
order — there is no separate section for it.

### 5. Emphasise test-driven development

Every task must be framed around a red-green cycle:

* **Write or update tests first** to reflect the desired behaviour.
  They will fail (or not compile). This is RED. **Run the tests and
  verify the failure.** Do not assume red — confirm it. A test that
  was never seen failing provides no signal.
* **Then change the production code** until the tests pass. This is
  GREEN.
* State clearly which tests are expected to break and when they should
  be restored.

Do not combine "update tests" and "update implementation" into a single
undifferentiated step. Even when they must be committed together, the
plan should make the reader think about the test expectations *before*
thinking about the implementation.

### 6. Expect refinement

The first draft of a plan is a starting point. The user will review it
and push back on design decisions, task scope, or approach. When they
do:

* Update the plan note and task todos in place using `bs update`:

  ```
  echo "<new body>" | bs update kb-N --content
  echo "<new body>" | bs update todo-X --content
  ```

* If a refinement reveals that a task was thinking too small (e.g.,
  extracting helper functions when the real answer is introducing a
  type), expand the task to match the better framing.
* If a refinement changes a design decision, update the Design
  Decisions section of the plan note *and* every task body that
  referenced the old decision.
* If a refinement implies changes to project principles or
  documentation, make those changes too.
