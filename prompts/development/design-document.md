# Design Document

Produce a written design document that explores a question about the
project and evaluates approaches to address it. The document is a
markdown file under `docs/designs/` (e.g.,
`docs/designs/design-the-thing.md`). It is a thinking tool — a place to lay out
the problem, explore the solution space, and reach a recommendation
before any code is written. It is not an implementation plan; it
should not break work into executable tasks.

## Inputs

The user will give you:

1. **The question** they want to explore, described in domain terms.
   They will typically point at the files or areas where the question
   arises.
2. **The motivation** — why the question matters.
3. Optionally, **a filename** for the document. If they don't provide
   one, derive a name from the topic (e.g., `design-cache-strategy.md`).

## Process

### 1. Analyse the codebase

Before writing anything, explore broadly. The user told you where the
question is visible, not where its effects end. Trace outward from
the starting files:

* What exists today? What are the relevant types, signatures,
  modules, and their relationships?
* What are the actual differences between things that look similar?
  Be precise: list them in a table when the comparison matters.
* Which layers of the codebase are affected? Quantify where useful
  (line counts, file counts, number of touch-points for a change).
* What tests exist? What documentation or principles govern the area?

Read the project documentation starting from `docs/index.md`. Ground
your analysis in the project's own vocabulary, layering rules, and
principles — do not invent standards.

The goal is to produce an accurate picture of **the current state** so
the approaches you propose later are grounded in reality, not
assumptions.

### 2. Write the document

The design document should contain these sections, in order:

* **Problem Statement** — a concise description of the question,
  grounded in specifics. The reader should understand the full scope
  of the problem without opening any files. Quantify where it helps
  (e.g., duplication costs, number of files a change would touch,
  performance characteristics). When the question involves things
  that look similar, include a table showing what actually differs
  between them.

* **Constraints** — hard requirements that any acceptable solution
  must satisfy (e.g., "must not break the existing CLI interface,"
  "must not add runtime dependencies," "must work within the current
  storage backend"). State these before exploring approaches so the
  reader can immediately discard solutions that violate them. Only
  include constraints that are genuinely non-negotiable — preferences
  and soft goals belong in the trade-offs discussion.

* **Approaches** — two to four realistic solutions, ordered from
  least to most invasive. For each approach:

  * **Mechanism** — how it works, concretely. Show the key types,
    signatures, or code patterns that would exist after the change.
    Code sketches are encouraged; they make the approach tangible.
  * **What changes for consumers** — does the public API change? Do
    callers need to update? Be specific about compatibility.
  * **What changes for tests** — do existing tests continue to work
    unchanged, or do they need mechanical updates?
  * **Impact** — what is gained and what is introduced. State the
    risk level and why.
  * **Limitations** — what this approach does *not* address.

  Approaches should build on each other when natural (A is a stepping
  stone to B, B to C). Make the incremental relationship explicit
  when it exists.

* **Rejected alternatives** — approaches that were considered and
  dismissed before full evaluation. For each one, name it briefly and
  state why it was ruled out (violates a constraint, clearly worse
  than a listed approach on every dimension, etc.). This prevents
  future readers from re-proposing ideas that have already been
  considered. Omit this section if no alternatives were dismissed.

* **What the approaches do NOT address** — issues or costs that
  survive all proposed approaches. For each one, explain *why* it is
  acceptable to leave it alone (too small, reflects genuine domain
  differences, concreteness is more valuable than abstraction, etc.).
  This section prevents the reader from wondering whether you missed
  something. Omit this section if there is nothing interesting to say.

* **Consequences and trade-offs** — analyse the approaches across
  dimensions that matter for the specific question. Examples:

  * What happens when a new instance of the pattern is added?
  * Readability impact at each level of invasiveness.
  * Type safety — does any approach weaken compile-time guarantees?
  * Migration path — can you stop at any step, or are some approaches
    all-or-nothing?
  * Performance, operational complexity, compatibility.

  Pick the dimensions that are relevant. Do not pad with dimensions
  that have nothing interesting to say.

* **Open questions** — anything the analysis surfaced that you cannot
  resolve alone. These are decisions that need the user's input before
  the recommendation can be finalized, or uncertainties that would
  change the evaluation if resolved differently. State each question
  clearly and, where possible, offer the options you see. Omit this
  section if there are no unresolved questions.

* **Recommendation** — state which approach you recommend and why, in
  terms of the trade-offs just discussed. Name the fallback (the less
  invasive option) and the future path (the more invasive option
  available later if circumstances change). If open questions remain
  that would change the recommendation, say so — a conditional
  recommendation is better than a premature one.

* **Files affected** — for the recommended approach, list every file
  that is new, modified, or unchanged-but-worth-confirming. Group by
  the nature of the change (new files, implementation changes, type
  reference updates, test updates, explicitly unchanged).

### 3. Maintain precision throughout

Every claim should be verifiable by reading the code:

* When you say two things are "identical", show what actually differs
  between them (even if the differences are small).
* When you give line counts, they should be approximate but honest —
  count them, don't guess.
* When you show code sketches, make them realistic. Use the project's
  actual types, module names, and conventions. A sketch that doesn't
  look like it belongs in the codebase is not useful.
* When you say something is "low risk", explain what would go wrong
  if you're mistaken and why that failure would be caught.

### 4. Stay at the design level

The purpose of this document is to explore and decide, not to
specify implementation steps. Do not break the recommended approach
into ordered tasks, execution plans, or red-green TDD cycles. Those
belong in an implementation plan, which is a separate activity that
comes after the design is accepted.

The document should give the reader enough detail to evaluate the
trade-offs and approve a direction. A code sketch that shows the
shape of a key type or interface is useful; a step-by-step guide to
modifying each file is too much.

### 5. Expect refinement

The first draft is a starting point. The user will push back on the
problem framing, the approach evaluation, or the recommendation. When
they do:

* Update the document in place — do not start a new file.
* If the user reframes the problem, update the Problem Statement and
  re-evaluate whether the approaches still make sense.
* If the user rejects an approach, keep it in the document (it
  records a considered alternative) but update the Recommendation
  section.
* If the analysis reveals that a principle or convention should
  change, note this in the document and flag it for the user.
