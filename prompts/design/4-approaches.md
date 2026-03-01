# Approaches and Research

Develop and evaluate approaches to satisfy the requirements in an
existing design document. This prompt is used iteratively — invoke it
repeatedly until all approaches are sufficiently detailed, all
research avenues are resolved, and a recommendation can be made.

## Inputs

The user will point you to the design document. It already contains a
problem statement, background, and refined requirements.

The user may also direct you to a specific task: "research X",
"flesh out approach Y", "compare the approaches." If they don't,
read the document and decide what needs attention next.

## Process

### 1. Read the document

Read the design document end to end. Understand where things stand:
what approaches exist, what research is outstanding, what's been
resolved since the last invocation.

### 2. Decide what to do

Each invocation does one of three things:

**A. Propose an approach.** When the document needs more approaches,
or when completed research makes a new approach viable, define one.
For each approach:

* **Mechanism** — how it works, concretely. Show the key types,
  signatures, or code patterns that would exist after the change.
  Code sketches are encouraged; they make the approach tangible and
  should use the project's actual types, module names, and
  conventions.
* **What changes for consumers** — does the interface change? Do
  existing callers, commands, or workflows need to update? Be
  specific about compatibility.
* **What changes for tests** — do existing tests continue to work,
  or do they need updates? What new tests are implied?
* **Limitations** — what this approach does not address.
* **Research needed** — open questions that must be answered before
  this approach can be fully evaluated. Be specific: "can SQLite
  handle this query pattern efficiently?" not "needs performance
  research." Each research item is a task for a future invocation.

When natural, order approaches from least to most invasive, and make
the incremental relationship explicit when one approach is a stepping
stone to another.

**B. Research an avenue.** When the document has unresolved research
items, pick one (or follow the user's direction) and investigate it.
Research means reading code, reading library sources, running
experiments, or looking up documentation — whatever the question
requires. Write up the findings in a **Research** section of the
document, covering:

* What did you learn?
* Which approaches does this affect, and how?
* Does this open new avenues or close existing ones?

Keep research findings in their own section — don't inline them into
the approaches. The approaches should be updated to reflect what was
learned (e.g., marking a research item as resolved, adjusting the
mechanism), but the detailed findings belong in Research so the
approaches stay clean and readable.

**C. Synthesize.** When all approaches are detailed and all research
is resolved, produce the closing sections of the design document:

* **Design Decisions** — key choices that emerged during the
  exploration, with the reasoning behind each. These are decisions
  that shaped the approaches or that any approach would need to
  make regardless. State the decision, the alternatives that were
  considered, and why this choice was made.

* **Rejected Alternatives** — approaches considered and dismissed
  before full evaluation. Name each briefly and state why it was
  ruled out. This prevents future readers from re-proposing ideas
  that have already been considered. Omit if none were dismissed.

* **Consequences and Trade-offs** — analyse the approaches across
  dimensions that matter for the specific problem. Pick the
  dimensions that are relevant; do not pad with dimensions that
  have nothing to say. Examples:
  * What happens when a new instance of the pattern is added?
  * Readability and maintainability impact.
  * Type safety — does any approach weaken compile-time guarantees?
  * Migration path — can you stop at any step, or is the change
    all-or-nothing?
  * Performance, operational complexity, compatibility.

* **Requirement Coverage** — for the recommended approach, map each
  requirement to how the approach satisfies it. If a requirement is
  only partially satisfied or requires compromise, say so explicitly.
  This prevents a convincing narrative from quietly dropping a
  requirement.

* **Recommendation** — which approach and why, in terms of the
  trade-offs just discussed. Name the fallback (the less invasive
  option) and the future path (the more invasive option available
  later). If any uncertainty remains that would change the
  recommendation, say so — a conditional recommendation is better
  than a premature one.

### 3. Update the document

Write your work into the design document. Keep the document coherent
as it grows across invocations — each new section should read as part
of a unified document, not as an append-only log.

### 4. Report what's next

At the end of each invocation, state clearly what remains: which
research avenues are still open, which approaches need more detail,
or whether the document is ready for synthesis. This gives the user
a clear picture of how many more invocations are likely needed.

## Guidance

* **Approaches should be realistic.** Don't include a strawman just
  to have a third option. Two strong approaches are better than two
  strong and one weak.

* **Research should be concrete.** "Read the SQLite documentation on
  partial indexes" is actionable. "Investigate performance" is not.

* **Don't collapse the process.** On the first invocation, it's
  tempting to propose all approaches, do all research, and
  synthesize in one pass. Resist this. The value of iteration is
  that research findings inform later approaches. An approach
  proposed before the relevant research is done is guesswork.
  Propose what you can ground in what you know, flag what you
  can't, and come back.

* **Precision carries over.** Every claim should be verifiable in
  the code. Code sketches should look like they belong in the
  codebase. When approaches build on the background section's
  findings, reference them specifically.

* **Design, not implementation plan.** The design document answers
  *what* to build and *which approach* to take. It does not specify
  file-by-file changes, function implementations, or task ordering —
  those belong in an implementation plan derived from the design.
  Code sketches illustrate the approach; they are not the
  implementation.
