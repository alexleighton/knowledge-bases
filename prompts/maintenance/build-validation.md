# Build Validation

Audit the project's build metadata for correctness and completeness.
This is a maintenance task — the goal is to ensure that the project
builds from a clean environment using only its declared dependencies.

## Scope

Build metadata lives in `dune-project` (source of truth) and the
generated `knowledge-bases.opam`. Dependencies are consumed in `dune`
files via `(libraries ...)` and `(pps ...)` clauses.

## Process

### 1. Static audit

Compare declared dependencies against actual usage:

1. **Grep all `(libraries ...)` and `(pps ...)` clauses** across every
   `dune` file in the project. Collect the full set of package names.
2. **Read `dune-project`'s `(depends ...)` block.** For each package
   found in step 1, verify it has a corresponding entry in `depends`.
   Flag any that are missing. Note: `unix` and `str` ship with the
   OCaml compiler and do not need opam declarations.
3. **Check for unused declarations.** For each entry in `depends`,
   verify the package appears in at least one `dune` file's
   `(libraries ...)` or `(pps ...)`. If it does not, determine whether
   it is pulled in transitively by another declared dependency and
   whether the explicit declaration is still needed.
4. **Check for exact pins.** Any `(= ...)` constraint should have a
   comment explaining why. If there is no justification, relax to
   `(>= ...)`.
5. **Check `(lang dune ...)` and `dune` constraint coherence.** The
   `lang` version controls which dune features the project's dune files
   may use. The `dune` package constraint controls which binary is
   required. Both should be as low as compatibility allows. Identify
   which dune features are actually used and whether the lang version
   is higher than necessary.

### 2. Validation run

Run the validation script against the current working tree:

```
bash scripts/validate-build.sh --local
```

This creates an isolated worktree and fresh opam switch with the
minimum declared OCaml compiler, installs dependencies, builds, and
runs tests.

If it fails, diagnose the failure:

* **Compiler error** (e.g., `Unbound module`) — the OCaml version
  constraint is too low. Raise the `(ocaml (>= ...))` bound.
* **opam solver error** — a dependency is missing from `dune-project`
  or has a conflicting constraint. Add or fix the entry.
* **Build error after deps install** — a library version constraint is
  wrong. Adjust the bound.

After fixing `dune-project`, regenerate the opam file:

```
dune build
```

Then re-run the validation script.

### 3. Lower-bound testing (optional)

Test whether declared lower bounds actually build:

```
bash scripts/validate-build.sh --local --lower-bounds
```

The script installs dependencies normally, then downgrades each
declared dependency to the oldest available version satisfying its
`>=` constraint. It prints version changes as it goes.

If this fails, a library lower bound is too low. Raise the bound and
re-run.

### 4. Cleanup

If `--keep` was used during debugging, remove the artifacts:

```
opam switch remove <switch-name> --yes
git worktree remove <worktree-path>
```

The switch name and worktree path are printed by the script when
`--keep` is active.

### 5. Report what you found

Summarise:

* Which dependencies were missing, added, or had constraints adjusted.
* Whether the `(lang dune ...)` version and `dune` constraint are
  coherent, and any changes made.
* Any declarations that appear unused and whether they can be removed.
* The result of the validation run (pass/fail and what was fixed).
