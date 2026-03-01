# Requirements Refinement

Revisit and tighten the requirements in an existing design document.
The document already contains a problem statement, background
analysis, initial requirements, and open questions. The background
analysis will have surfaced observations — constraints, adjacent
features, gaps, patterns — that the initial requirements didn't
account for. This step incorporates those findings.

## Inputs

The user will point you to the design document.

## Process

### 1. Read the document

Read the design document end to end. Pay particular attention to the
Background section's observations and the open questions from the
requirements step. These are the two main sources of refinement.

### 2. Reconcile

Work through the observations and open questions systematically.
For each one, decide what it means for the requirements:

* **New requirement** — the observation reveals functionality that
  was missing. Add it to the requirements list.
* **Modified requirement** — an existing requirement needs to be
  more specific, more general, or differently scoped in light of
  what the codebase analysis found.
* **Constraint** — the observation doesn't define what to build but
  limits how it can be built. Note it as a constraint alongside the
  affected requirement.
* **No action** — the observation is useful context but doesn't
  change the requirements. Leave it in the background section; it
  will inform the approach.

### 3. Check for cross-cutting impact

Review the full requirements list looking for cross-cutting
concerns — requirements that, taken together, imply changes to parts
of the system that no single requirement names. The background
section's description of adjacent functionality is the place to look.
If the requirements would leave a gap (a feature that should be
updated but isn't mentioned), add a requirement to close it.

### 4. Update the document

Edit the requirements section in place:

* Add new requirements, remove any that the analysis showed are
  unnecessary, and update wording where it needs to be more precise.
* Where a requirement changed, briefly note why (e.g., "refined after
  codebase analysis showed X uses pattern Y").
* Move resolved open questions out of the Open Questions section. If
  they became requirements or constraints, they now live there. If
  they turned out to be irrelevant, remove them.
* Add any new open questions that the refinement surfaced — things
  that need research or further discussion before the approach can
  be chosen.

Remove the first-pass marking from the requirements section.

### 5. Ask if needed

This step is mostly autonomous — the codebase analysis provides the
facts, and reconciliation is mechanical. But if the refinement
surfaces a genuine choice that only the user can make (e.g., two
conflicting requirements that can't both be satisfied, or a
discovered constraint that invalidates a requirement the user cares
about), stop and ask before proceeding.
