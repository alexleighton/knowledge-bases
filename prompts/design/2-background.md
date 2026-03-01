# Background and Status Quo

Add a background section to an existing design document. The
requirements are already written; now analyse the codebase to
understand the current state of everything the requirements touch.
The goal is to give a future reader (or a future prompt) enough
context about how things work today to make informed design
decisions.

## Inputs

The user will point you to the design document. It already contains a
problem statement, requirements, and open questions from the previous
step.

## Process

### 1. Read the document

Read the design document and the project documentation
(`docs/index.md` and anything it links to). Understand the
requirements well enough to know where to look in the code.

### 2. Analyse the codebase

Explore the code guided by the requirements — not the whole codebase,
but everything the requirements touch or might touch. Trace outward
from the obvious starting points:

* **What exists today** — the relevant types, modules, signatures,
  and their relationships. Show enough structure that the reader
  understands the shape of the code without opening files.
* **How data flows** — for the areas the requirements affect, how
  does data move through the system? Which layers are involved?
  Follow the project's architectural layering.
* **Patterns in use** — what conventions does the codebase follow in
  the affected areas? New functionality should either follow these
  patterns or have a good reason not to.
* **Tests and coverage** — what tests exist for the affected areas?
  What testing patterns are used?
* **Adjacent functionality** — features that aren't directly named
  in the requirements but live nearby in the code. These are the
  features most likely to need adjustment when the new functionality
  lands.

Quantify where it helps: line counts, file counts, number of
touch-points for a change. Be precise — count things, don't
estimate.

### 3. Write the background section

Insert a **Background** section into the design document, after the
Problem Statement and before the Requirements. It should cover:

* **Current state** — a narrative description of how the relevant
  parts of the system work today. Use the project's own vocabulary.
  Include type signatures or short code excerpts when they clarify
  the structure better than prose would.
* **Relevant architecture** — which layers, modules, and boundaries
  are involved. How the affected code fits into the broader system.
* **Existing patterns** — conventions the codebase follows that the
  new feature should be aware of. Note where existing features solve
  a similar problem and how.
* **Observations** — anything the codebase analysis surfaced that
  the requirements didn't anticipate. This could be:
  * Constraints imposed by the current implementation.
  * Existing functionality that would need to change.
  * Patterns that suggest a particular design direction.
  * Gaps or inconsistencies in the current system.
  * Technical debt that interacts with the requirements.

  Don't try to resolve these here — just surface them clearly. The
  requirements refinement step will decide what to do with them.

### 4. Precision

Every claim must be grounded in the code. When you say something
"uses" or "follows" a pattern, point to where. When you say two
things are similar, show what actually differs. When you give counts,
make them accurate. A background section full of vague impressions is
worse than none at all — it creates false confidence.

### 5. Scope

Stay descriptive, not prescriptive. This section documents what
*is*, not what *should be*. Do not propose solutions, recommend
approaches, or suggest how requirements should change. Those belong
in later steps. The background section earns its keep by being a
reliable reference that the rest of the document can build on.
