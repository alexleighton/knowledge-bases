# Requirements Distillation

Produce the opening sections of a design document: a problem
statement and an initial set of requirements. The design document is a
markdown file at the top level of the project (e.g.,
`design-cache-strategy.md`). This is a first pass — the requirements
will be revisited after codebase analysis.

## Inputs

The user will give you:

1. **A problem or feature description** — could be a detailed
   specification, a rough idea, a reference to other documents, or
   something informal.
2. Optionally, **a filename** for the design document. If they don't
   provide one, derive a name from the topic.

## Process

### 1. Orient

Read everything the user has given you. If they reference other
documents, read those too.

Then get oriented in the project: read the documentation index
(`docs/index.md`) and any documents it links to that seem relevant,
and run the program with `--help` to see its current interface. You
are not doing a deep codebase analysis — that comes later. The goal
is to learn the project's vocabulary, its existing features, and its
conventions well enough to ask informed questions. You should be able
to name the things that already exist when asking how new
functionality interacts with them.

### 2. Ask questions

Before writing the document, stop and ask the user questions
interactively. Wait for their answers before proceeding. You are
looking for:

* **Ambiguities** — where the description could mean more than one
  thing.
* **Unstated requirements** — functionality the user probably expects
  but hasn't said. Think about what a user of the feature would
  assume works.
* **Interaction points** — how the new functionality touches things
  that already exist. If implementing X means existing feature Y
  should behave differently, surface that. These are the requirements
  most likely to be overlooked.
* **Scope boundaries** — what is explicitly not part of this work.
* **Priorities** — which aspects matter most when trade-offs arise.
* **Validity** — whether this is the right problem to solve. If the
  description sounds like a solution to an unstated problem, ask what
  the underlying problem is. If the feature seems like it might not
  carry its weight, say so. The right output of a design process is
  sometimes "don't build this."

Ask your most important questions. Not every question needs an answer
right now — some are better answered by codebase analysis or research
later. If the user defers a question, note it as an open question.

Do not write the document until you have asked questions and received
answers.

### 3. Write the document

Create the design document with these sections:

* **Problem Statement** — a concise summary in your own words. The
  reader should understand the scope and motivation without reading
  the original description. State what exists today, what is missing
  or broken, and why the gap matters.

* **Requirements** — a numbered list. Each requirement should be
  specific enough that you could later verify whether an
  implementation satisfies it. Order them to best illuminate the
  problem — by importance, by logical dependency, or by area.

  Where a requirement implies changes to existing functionality, say
  so explicitly. "Adding relations" is incomplete; "adding relations,
  which must be visible in `show` output and queryable via `list
  --related`" makes the cross-cutting impact clear.

  For each requirement, a brief phrase of rationale is useful when the
  reason isn't obvious — it helps later when deciding whether to keep,
  modify, or drop a requirement that turns out to be costly.

* **Scenarios** — concrete before/after examples that illustrate the
  requirements in action. Each scenario should show a specific
  starting state, a user action, and the expected outcome. Use the
  project's actual commands, data formats, and vocabulary. Good
  scenarios make abstract requirements tangible and double as test
  cases later — if you can't write a scenario for a requirement, the
  requirement is probably too vague.

* **Constraints** — things the implementation must not break or
  change, known before any codebase analysis. These are different
  from requirements: requirements say what to build, constraints say
  what must remain true while building it. Examples: "must not change
  the on-disk format", "existing CLI commands must continue to work",
  "no new runtime dependencies." Codebase analysis may surface
  additional constraints later; these are the ones the user already
  knows.

* **Open Questions** — anything that came up during the conversation
  and remains unresolved. For each, note what you think would answer
  it: codebase analysis, research into a library or technique, or
  further discussion with the user. Some of these will become
  requirements; others will become constraints on the solution space.

Mark the requirements section as a first pass. It will be refined
after codebase analysis in a subsequent step.

### 4. Precision

Prefer stating requirements in terms of observable behavior rather
than implementation. "The user can filter todos by relation" is a
requirement. "Add a `--related` flag to the `list` command" is a
design decision — those come later. When you already know the shape
of the interface, it's fine to be concrete, but distinguish between
what the feature must accomplish and how it might be surfaced.

Avoid vague qualifiers. "Fast" is not a requirement; "results appear
within 200ms for a knowledge base with 1,000 items" is. If you
can't quantify, describe the scenario that would constitute failure.

### 5. Expect refinement

This is not the final word. Codebase analysis will surface
interactions, constraints, and edge cases that this initial pass
cannot anticipate. The requirements will be revisited and tightened
in a later step. Treat this document as a living artifact — update
it in place, do not create new files.

## Examples

See `docs/designs/` for completed design documents that went through
all four steps of the pipeline (requirements → background →
refinement → approaches).
