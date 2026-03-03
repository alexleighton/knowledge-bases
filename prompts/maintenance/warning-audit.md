# Warning Suppression Audit

Scan the codebase for warning suppressions and evaluate whether each one
is still justified. This is a maintenance task — the goal is to remove
suppressions that have outlived their purpose, not to add new ones.

## What to scan for

Search OCaml sources (`*.ml`, `*.mli`) for these patterns:

* `[@warning "…"]` — per-expression warning suppression
* `[@@warning "…"]` — per-item warning suppression
* `[@@@warning "…"]` — per-file warning suppression

## Process

### 1. Collect all suppressions

Grep the codebase for the patterns above. For each hit, record:

* **File and line** — where the suppression lives.
* **Warning number(s)** — which warnings are being silenced (e.g. `-4`,
  `-69`).
* **Scope** — expression, item, or file-level.
* **Justification** — the comment accompanying the suppression, if any.

### 2. Evaluate each suppression

For each suppression, determine whether it is still needed:

1. **Read the surrounding code.** Understand why the warning would fire
   without the suppression.
2. **Check whether the condition still holds.** A suppression added
   because a record field was unused may no longer be needed if the
   field is now read. A fragile-match suppression may no longer be
   needed if the match has been made exhaustive.
3. **Try removing it.** Run `dune build` with the suppression removed.
   If the build succeeds with no new warnings, the suppression is dead
   weight.

Classify each suppression into one of:

* **Still needed** — the underlying reason persists and the accompanying
  comment explains it. No action required.
* **Removable** — the condition that motivated it no longer holds. Remove
  the suppression (and its explanatory comment, if any).
* **Needs investigation** — you cannot confidently determine whether it
  is still needed. Flag it for the user.

### 3. Apply changes and verify

Remove all suppressions classified as removable, then run:

```
dune build
dune runtest
```

Both must pass cleanly. If removing a suppression surfaces a real
warning, fix the underlying code rather than keeping the suppression.

### 4. Report what you found

Summarise:

* Which suppressions were removed and why they were no longer needed.
* Which suppressions remain and the reason each is still justified.
* Any suppressions or notes that need the user's attention.
