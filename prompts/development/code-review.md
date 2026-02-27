# Code Review

Review code changes on a branch and propose concrete improvements.
The review is a conversation: present findings, then act on the user's
decisions.

## Inputs

The user will give you:

1. **The changes** — typically a branch diff, a set of files, or a
   pointer like "review the current branch."
2. **Context** — optionally, a plan document or description of what the
   changes were attempting to achieve.

## Process

### 1. Read the project documentation

Before looking at any code, start from `docs/index.md` and read every
document it references. The principles and architecture docs define
the vocabulary the project uses, the layering rules, the testing
strategy, and the conventions that code is expected to follow. Your
suggestions must be grounded in these — do not invent standards that
contradict or duplicate what the project already says.

Pay particular attention to:

* **Architecture** — layer boundaries, where different kinds of code
  belong, and naming conventions.
* **Principles** — per-area rules (`lib/`, `bin/`, `test/`). These
  tell you what counts as duplication, where validation belongs, how
  tests are organised, and what should not be tested.
* **Test structure** — understand the distinction between unit tests
  (`test/`) and integration tests (`test-integration/` or similar).
  Know where a new test belongs before proposing one.

### 2. Understand the intent

If a plan document or description is provided, read it fully. The plan
states what the change set out to do, what design decisions were made,
and what trade-offs were accepted. Evaluate the code against the plan's
goals, not against an idealised rewrite.

### 3. Analyse the changes in context

Read every changed file, then trace outward:

* What depends on the changed modules? What do they depend on?
* Are there existing helpers, utilities, or conventions that the new
  code should be using but isn't?
* Do the changes leave documentation stale?
* Do the changes leave tests in the wrong place or with gaps?

Build your understanding from the code and docs — do not guess at
project structure.

### 4. Present findings

Produce a numbered list of suggestions. For each one:

* **State the observation** — what you found and where.
* **Explain why it matters** — grounded in project principles,
  consistency, correctness, or maintainability.
* **Propose a concrete action** — what to change, or what decision the
  user needs to make. When there are multiple reasonable options, name
  them briefly and say which you lean toward.

Keep each suggestion independent. The user will accept, reject, or
redirect each one individually.

Avoid these failure modes:

* **Inventing work the project doesn't want.** If the architecture
  doc lists a table of "examples" and explicitly says it is not
  exhaustive, do not propose adding every new module to it.
* **Flagging abstraction opportunities where concepts are genuinely
  distinct.** Two modules with similar structure but different domain
  meaning are not duplication — they are the abstraction working as
  intended. Only flag duplication when the same *concept* is repeated.
* **Misplacing test suggestions.** Understand the project's test
  layout before recommending where a test goes. A test that calls a
  library function directly is a unit test and belongs in `test/`. A
  test that drives a binary or exercises cross-layer behaviour belongs
  in integration tests.
* **Proposing changes that only matter in the abstract.** Every
  suggestion should connect to a concrete improvement the user can
  act on. "Consider whether X" is not a suggestion; "Change X to Y
  because Z" is.

### 5. Act on decisions

The user will respond to each suggestion. When they do:

* **Accepted** — implement the change. Run the tests. Confirm green.
* **Accepted with redirection** — the user agrees with the goal but
  corrects the approach. Follow their direction, not your original
  proposal.
* **Rejected** — drop it. Do not re-argue.

Make all accepted changes in one pass where possible. Run the full
test suite after all changes, not after each individual edit.

### 6. Adapt existing code, don't just add

When a suggestion involves using an existing helper or convention,
adapt the helper if it doesn't quite fit rather than working around
it. The goal is uniformity: one way of doing things, used everywhere.
If a helper's API needs to change, update it, update all its callers,
and update its tests.
