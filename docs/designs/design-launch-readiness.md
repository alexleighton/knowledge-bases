# Design: Launch Readiness (opam release)

## Problem Statement

`bs` is a functional CLI tool with a complete feature set, a test suite,
and a dual-format storage architecture — but it exists only as a local
development build. There is no way for someone outside the repository to
install it.

The goal is to publish `knowledge-bases` as a package on the official
opam repository so that users can run `opam install knowledge-bases` and
get the `bs` binary. This requires filling gaps in project metadata,
establishing a release workflow, and meeting opam-repository's
submission standards.

Today:
- The `dune-project` defines a package but is missing required metadata
  fields (`source`, `license`, `authors`, `maintainers`).
- There is no CHANGES file.
- There is no release workflow (`dune-release` or manual).
- The README is developer-facing, not user-facing.
- The library (`kbases`) is internal-only, which is intentional — only
  the `bs` binary is distributed.

## Background

### Project structure

The codebase has 143 source files across four directories:

| Directory          | `.ml` files | `.mli` files | Lines  |
|--------------------|-------------|--------------|--------|
| `lib/`             | 36          | 36           | 13,446 |
| `bin/`             | 16          | 0            | 1,090  |
| `test/`            | 35          | 0            | 4,143  |
| `test-integration/`| 16          | 0            | 3,389  |

The library is named `kbases` in `lib/dune` with no `(public_name ...)`
— it is deliberately internal. The only published artifact is the `bs`
executable, declared in `bin/dune` as `(public_name bs)` under
`(package knowledge-bases)`.

### Library architecture

`lib/` is organised into four layers with downward-only dependencies
(documented in `docs/lib/architecture.md`):

```
Service    → orchestration of business operations
Repository → persistence and storage (SQLite)
Control    → control flow, effects, I/O
Data       → domain types and value objects
```

**Data layer** (12 modules). Pure domain types with abstract `type t`,
smart constructors, and validation. Key types: `Todo.t` (statuses:
`Open | In_Progress | Done`), `Note.t` (statuses: `Active | Archived`),
`Identifier.t` (human-friendly `<namespace>-<raw_id>`), `Relation.t`
(source/target TypeIds, kind, bidirectional, blocking), `Uuid.Typeid.t`
(UUIDv7-based type identifiers), `Title.t`, `Content.t`.

**Repository layer** (7 modules). SQLite-backed persistence. Each
module exposes an opaque `type t` initialised from a `Sqlite3.db`, with
its own `type error`. `Root` is the coordinator: `Root.init` opens the
single database connection, creates all repository handles, and exposes
accessors. A `Jsonl` module handles the `.kbases.jsonl` file — the
git-mergeable serialisation format.

**Control layer** (3 modules). `Assert` (precondition combinators),
`Exception` (formatted `Invalid_argument` constructors), `Io`
(stdin/file I/O).

**Service layer** (9 modules). `Kb_service` is the public facade the
CLI calls. It delegates to focused helpers: `Item_service` (identifier
parsing, cross-entity lookup), `Query_service` (list, show),
`Mutation_service` (update, claim, resolve, archive, next),
`Relation_service` (relation creation), `Sync_service` (flush/rebuild),
`Lifecycle` (init, open), `Git` (repo detection, `.git/info/exclude`),
`Parse` (JSONL record parsing). Error types are translated at the
service boundary — the CLI never sees raw repository errors.

### Dual-format storage

Data lives in SQLite (`.kbases.db`) at runtime and is serialised to
`.kbases.jsonl` for git. The JSONL file is designed for conflict-free
merges: entity lines are sorted by TypeId, and the header line contains
only stable fields (`_kbases`, `namespace`). `Sync_service` manages
the two formats: `flush` writes SQLite → JSONL, `force_rebuild` reads
JSONL → SQLite, and `rebuild_if_needed` uses a content hash
(`Digest.file`) to detect external changes on open.

The `.kbases.db` file is excluded from git via
`.git/info/exclude` (written during `bs init`). The `.kbases.jsonl`
file is committed.

### CLI structure

`bin/` contains 13 command modules plus `main.ml`,
`cmdline_common.ml`, and `app_context.ml`. The CLI is built on
cmdliner 2.0. Commands:

| Module           | Command         | Args                      |
|------------------|-----------------|---------------------------|
| `Cmd_init`       | `init`          | `-d`, `-n`, `--json`      |
| `Cmd_add`        | `add note/todo` | `TITLE`, `--content`, relation flags, `--json` |
| `Cmd_list`       | `list`          | `[TYPE]`, `--status`, `--available`, `--json` |
| `Cmd_show`       | `show`          | `IDENTIFIER...`, `--json` |
| `Cmd_update`     | `update`        | `IDENTIFIER`, `--status`, `--title`, `--content`, `--json` |
| `Cmd_resolve`    | `resolve`       | `IDENTIFIER`, `--json`    |
| `Cmd_close`      | `close`         | alias for `resolve`       |
| `Cmd_archive`    | `archive`       | `IDENTIFIER`, `--json`    |
| `Cmd_claim`      | `claim`         | `IDENTIFIER`, `--show`, `--json` |
| `Cmd_next`       | `next`          | `--show`, `--json`        |
| `Cmd_relate`     | `relate`        | `SOURCE`, relation flags, `--json` |
| `Cmd_flush`      | `flush`         | `--json`                  |
| `Cmd_rebuild`    | `rebuild`       | `--json`                  |

Every command supports `--json` for machine-readable output using a
consistent `{"ok": true/false, ...}` envelope. `App_context` wraps
`Root.t` and `Kb_service.t` with `init`/`close` lifecycle management,
and all commands use `Fun.protect ~finally` for cleanup.

Patterns across commands: text output goes to stdout, errors to stderr
via `exit_with_error`. `Cmd_close` is implemented as a pure alias
(delegates to `Cmd_resolve.run`). `Cmd_claim` and `Cmd_next` share
output helpers via `Cmd_show` and `Cmd_claim`. Only `show` accepts
multiple identifiers; all other commands operate on a single item.
`Cmd_next` uses exit code 123 for "nothing available" — the only
command with a non-standard exit code.

Relation flags (`--depends-on`, `--related-to`, `--uni`, `--bi`,
`--blocking`) are defined in `cmdline_common.ml` and shared across
`add` and `relate`.

### Packaging metadata — current state

`dune-project` (22 lines) declares `(lang dune 3.11)` and a single
`(package ...)` with a `(depends ...)` block. It does not contain
`(source ...)`, `(license ...)`, `(authors ...)`, or
`(maintainers ...)`.

The generated `knowledge-bases.opam` (33 lines) inherits this gap.
Running `opam lint` today produces:

```
error 23: Missing field 'maintainer'
warning 25: Missing field 'authors'
warning 35: Missing field 'homepage'
warning 36: Missing field 'bug-reports'
warning 68: Missing field 'license'
```

Error 23 (`maintainer`) is a hard rejection by opam-repository.
Warnings 35, 36, and 68 are generated automatically by
`(source (github ...))` plus `(license ...)`.

The dependency list includes a dune version conflict: `(lang dune
3.11)` contributes `>= 3.11` while the explicit dep says
`>= 3.20.2`. The generated opam file shows `{>= "3.11" & >= "3.20.2"}`
— redundant but not incorrect. The `3.20.2` constraint is the binding
one.

`LICENSE.txt` exists at the repository root (MIT, copyright 2025 Alex
Leighton). No `(license ...)` stanza references it yet.

There is no CHANGES file anywhere in the repository.

### Build under `-p`

The opam build sequence invokes `dune build -p knowledge-bases`, which
restricts visibility to the named package. The `bin/dune` file
correctly declares `(package knowledge-bases)` on the executable,
so `-p` should find it. The library `kbases` has no `(package ...)`
stanza — under `-p`, dune treats unpackaged libraries as available
if they are in the same project. The test dune files use
`(inline_tests)` which `-p` with `@runtest` will exercise when
`with-test` is set.

The `ocaml-lsp-server` dependency is tagged `with-dev-setup` — opam
ignores this during normal installs. `ppx_expect` and
`ppx_inline_test` are tagged `with-test`. `odoc` appears in the
generated opam file (tagged `with-doc`) though it is not declared in
`dune-project` — dune adds it automatically.

### README

The current `README.md` (66 lines) is developer-oriented. It opens
with a one-line description, then lists an MVP feature checklist
(partially outdated — references `bs create` which became `bs add`),
followed by development setup instructions (opam switch, dune build,
dune runtest, git hooks). There is no installation section, no
quick-start example for end users, and no pointer to `bs --help`.

### Test suite

**Unit tests** (`test/`, 35 files, 4,143 lines). Organised to mirror
`lib/`: `test/data/`, `test/repository/`, `test/service/`, plus
`test/control/`. All use ppx_expect (`let%expect_test`) with inline
snapshot assertions. Repository tests use an in-memory SQLite database
via `test/repository/test_helpers.ml`. Service tests create temporary
git repositories and clean them up with `Fun.protect`
(`test/service/test_helpers.ml`). Every `lib/` module with meaningful
logic has a corresponding `_expect.ml` file.

**Integration tests** (`test-integration/`, 16 files, 3,389 lines).
Exercise the `bs` binary as a subprocess. The dune file depends on
`%{bin:bs}` and `(universe)` (forces re-run on every build). The
test helper normalises paths (`<DIR>`) and TypeIds (`<TYPEID>`) for
reproducible snapshots. Tests cover every command: `init`, `add todo`,
`add note`, `list`, `show`, `update`, `resolve`, `close`, `archive`,
`claim`, `next`, `relate`, `flush`, `rebuild`, plus a multi-phase
`workflow_expect.ml` that exercises a full lifecycle.

### Existing patterns relevant to requirements

**Error output.** All commands route errors through
`Cmdline_common.exit_with_error`, which prints `Error: <msg>` to
stderr (text mode) or `{"ok": false, "reason": "error", "message":
"<msg>"}` to stdout (JSON mode). Exit code is 1 except `next` which
uses 123 for "nothing available".

**Man pages.** The CLI uses cmdliner's `~man` parameter on every
`Cmd.info` call with `EXAMPLES` sections. Cmdliner can generate man
pages from these, but no `(install ...)` stanza ships man pages
currently. The root command includes a hand-written `COMMANDS` section
listing all subcommands with one-line descriptions.

**Git dependency.** `Service.Git.find_repo_root` shells out to
`git rev-parse --show-toplevel`. `Lifecycle.open_kb` fails with a
clear message if not inside a git repository. This is load-bearing —
the JSONL sync, `.git/info/exclude` management, and namespace
derivation all depend on the git root.

### Observations

1. **The `(lang dune 3.11)` line and the `(dune (>= "3.20.2"))`
   dependency are inconsistent.** The lang line sets a minimum feature
   level for the dune language; the dependency constrains the installed
   dune version. If no dune 3.11-specific features are used, the lang
   line could be raised to 3.20 to match. If they are, the gap is
   intentional. The generated opam file's `{>= "3.11" & >= "3.20.2"}`
   is harmless but looks like an oversight.

2. **The README references `bs create`, which no longer exists.** The
   command was renamed to `bs add`. The MVP checklist is stale.

3. **`ocaml-lsp-server` is listed as a dependency.** It uses the
   `with-dev-setup` tag, which opam ignores on install — but it still
   appears in the opam file. `opam-repository` reviewers may flag it
   as unusual.

4. **No `.mli` files in `bin/`.** The `bin/dune` file disables
   warning 70 (missing mli). This is a deliberate project convention
   documented in `docs/bin/principles.md` — `bin/` modules are thin
   CLI wiring, not reusable interfaces.

5. **Integration tests depend on `(universe)`.** This causes them to
   re-run unconditionally. Under `dune build -p knowledge-bases
   @runtest`, these tests will execute on every opam CI build. If they
   are slow or flaky in constrained CI environments, this could cause
   opam-repository CI failures.

6. **`Cmd_show` exports helpers used by other commands.**
   `Cmd_claim` and `Cmd_next` import `Cmd_show.item_to_json`,
   `Cmd_show.format_show_result`, and `Cmd_show.relation_entry_to_json`.
   This creates coupling within `bin/` — not a packaging issue, but
   relevant if the CLI structure is reviewed for consistency
   (requirement 9).

7. **Exit code 123 in `Cmd_next` is undocumented.** The `--help`
   output does not mention the special exit code for "no available
   todos". This is relevant to CLI readiness (requirement 9) since
   it becomes a compatibility commitment on release.

8. **`Digest.file` is used for content hashing.** `Sync_service`
   uses OCaml's `Digest` module (MD5) to detect JSONL changes. This
   is a stdlib dependency with no portability concern, but MD5 is
   deprecated for security purposes. For content-change detection it
   is adequate.

9. **The `scripts/` directory contains development tooling** (6 files:
   `setup-dev-env.sh`, `install-pre-push-hook.sh`, `validate-build.sh`,
   `watch-build.sh`, `find-unused.py`, and a dune file). These are not
   packaged — they have no `(package ...)` stanza — and will not
   appear in a release tarball built by `dune-release distrib`.

10. **No `dune subst` watermarks are present.** The `dune subst`
    command (run by opam during dev builds) substitutes `%%VERSION%%`
    markers in source files. The codebase does not use any version
    watermarks currently. This is fine for an initial release but means
    `bs --version` cannot report its version without adding one.

## Requirements

### Packaging metadata

1. **Complete `dune-project` metadata.** Add `(source ...)`, `(license
   ...)`, `(authors ...)`, and `(maintainers ...)` stanzas so that `dune`
   generates a fully valid `.opam` file. The source stanza should point
   to `https://github.com/alexleighton/knowledge-bases`.

   *Rationale: opam-repository rejects packages missing `maintainer`,
   `license`, `dev-repo`, `homepage`, or `bug-reports`. The `(source
   (github ...))` stanza generates the last three automatically.*

2. **Fix the dune version constraint.** Raise `(lang dune 3.11)` to
   `(lang dune 3.20)` to match the explicit `(dune (>= "3.20.2"))`
   dependency. The current lang line contributes a redundant `>= 3.11`
   to the generated opam file; aligning them eliminates the overlap and
   makes the actual minimum version obvious.

3. **Remove `ocaml-lsp-server` from the dependency list.**
   `ocaml-lsp-server` appears in the generated opam file with a
   `with-dev-setup` tag. Although opam ignores this during normal
   installs, LSP servers are editor tooling, not package dependencies —
   opam-repository reviewers will flag it. Remove it from `dune-project`
   and verify that no other dev-only tools leak into the published
   dependency list.

4. **Create a `CHANGES.md` file** in a format compatible with
   `dune-release`. Use ATX-style headers with the version as the first
   word (e.g., `## 0.1.0 (2026-03-06)`). The first entry documents the
   initial release. Optionally use keepachangelog sections (`### Added`,
   `### Fixed`, etc.) — `dune-release` >= 1.6.0 supports them.

   *Rationale: `dune-release` parses the CHANGES file to extract release
   notes for the GitHub release and opam-repository PR. Research
   confirmed `CHANGES.md` is the dominant convention; `dune-release`
   auto-detects files named `changes` or `changelog` with any extension.*

5. **Choose a version number** for the initial release and tag it.
   opam's solver does not treat `0.x` specially (unlike npm's semver) —
   the choice is purely a social signal about stability. Ecosystem
   precedent: cmdliner started at `0.9.0`, dune at `1.0.0`, ocamlformat
   at `0.9.1` (still pre-1.0 after 8 years). A `0.1.0` starting version
   is appropriate for a functional but pre-1.0 tool.

6. **Declare platform availability.** Add `available: os != "win32"` to
   the opam metadata. The production code's `Unix` usage is close to
   portable, but the test infrastructure uses `Unix.fork`,
   `Unix.execve`, `Unix.kill`, and `/dev/null` — all unavailable or
   broken on native Windows. The `sqlite3` C bindings are technically
   buildable on Windows via MinGW/Cygwin but add friction for no
   practical benefit. Unix-only is the standard posture for OCaml CLI
   tools (e.g., Jane Street's `core` uses the same restriction).

   *Constraint: verify whether `dune-project`'s `(package ...)` stanza
   supports an `(available ...)` field. If not, add the constraint via
   an opam template file or post-generation edit.*

### Release workflow

7. **Establish a `dune-release` workflow** for cutting releases. The
   workflow should: tag the version, build a tarball, upload it to GitHub
   Releases, and open a PR to `ocaml/opam-repository`.

   *Rationale: `dune-release` automates the error-prone parts —
   checksumming the tarball, formatting the opam-repository PR, and
   filling in the `url` block.*

8. **Ensure the package builds cleanly under `opam`'s build commands.**
   The standard opam build sequence is:
   ```
   dune subst   # (dev only — substitutes version watermarks)
   dune build -p knowledge-bases -j <jobs> @install @runtest
   ```
   Verify this works — `-p` restricts the build to the named package and
   may surface issues not visible in a full `dune build`. Pay particular
   attention to integration tests: they depend on `(universe)`, which
   forces unconditional re-runs. Under opam-repository CI, this means
   they execute on every build. If they are slow or flaky in constrained
   CI environments, they could cause opam-repository CI failures.

### Repository presentation

9. **Polish the README for public consumption.** The current README is
   developer-oriented with a stale MVP checklist (references `bs create`,
   which was renamed to `bs add`). Rewrite to cover: what `bs` is,
   installation (`opam install knowledge-bases`), a quick-start example,
   and a pointer to `bs --help`. Remove or replace the outdated checklist.

10. **Verify the LICENSE file is correctly referenced.** The file exists
    as `LICENSE.txt` (MIT, copyright 2025 Alex Leighton). The
    `dune-project` `(license MIT)` stanza should match.

### CLI readiness

11. **Review the CLI interface for consistency before release.** Once
    published, the command surface becomes a compatibility commitment.
    Review: flag naming conventions, output format consistency, error
    message quality, and whether the current command structure
    accommodates likely future commands without breaking changes.

    Specific items to address:
    - Exit code 123 in `Cmd_next` (for "no available todos") is
      undocumented in `--help` output. Since this becomes a
      compatibility commitment on release, it should be documented
      or reconsidered.
    - `Cmd_show` exports helpers consumed by `Cmd_claim` and
      `Cmd_next` — not a packaging issue, but a coupling pattern
      to be aware of during review.

    *Rationale: post-release breaking changes require a major version
    bump and migration guidance. Better to catch inconsistencies now.*

12. **Add version reporting.** The codebase has no `%%VERSION%%`
    watermarks for `dune subst`. Without one, `bs --version` (or
    equivalent) cannot report the installed version. Add a version
    watermark so the release workflow produces a version-aware binary.

    *Rationale: `dune subst` replaces `%%VERSION%%` markers during
    release builds. Without a marker, the installed binary has no way
    to report its version.*

### CI and quality

13. **Verify the package passes `opam lint`.** Run `opam lint` on the
    generated `.opam` file and fix any warnings or errors.

14. **Test the build on Linux.** Development appears to be on macOS.
    opam-repository CI will build on multiple Linux distributions and
    compiler versions. Ensure the build succeeds outside the development
    environment. The integration tests' `(universe)` dependency means
    they will run unconditionally in CI — verify they pass reliably
    in constrained environments.

    *Rationale: integration tests use `(universe)`, causing unconditional
    re-runs. opam-repository CI will exercise them on every build —
    failures there block the package from being published.*

## Scenarios

### Scenario 1: First-time user installs `bs`

Starting state: a user has opam configured with the default repository.

```
$ opam install knowledge-bases
[...]
$ bs --help
NAME
       bs - Knowledge base management CLI.
[...]
$ mkdir myproject && cd myproject && git init
$ bs init
Initialised knowledge base: [...]
$ echo "Try out bs" | bs add todo "First todo"
Created todo: kb-0 (todo_01...)
```

Expected: the binary is on their PATH, works immediately, and the
`--help` output is clear enough to get started without external docs.

### Scenario 2: Cutting a release

Starting state: maintainer has changes ready to release on `main`.

```
$ # Update CHANGES file with new version entry
$ git commit -am "Prepare 0.3.0 release"
$ dune-release tag
$ dune-release distrib
$ dune-release publish distrib
$ dune-release opam pkg
$ dune-release opam submit
```

Expected: a PR appears on `ocaml/opam-repository` with the correct
tarball URL, checksum, and metadata. CI passes. Maintainers merge.

### Scenario 3: opam-repository CI builds the package

Starting state: PR submitted to opam-repository.

```
# opam-repo-ci runs approximately:
opam lint packages/knowledge-bases/knowledge-bases.X.Y.Z/opam
opam install knowledge-bases.X.Y.Z  # on multiple OS/compiler combos
```

Expected: lint passes with no errors or warnings. Build and tests pass
on Linux and macOS with OCaml >= 5.4.0.

## Constraints

- **No new runtime dependencies.** The current dependency set (SQLite,
  cmdliner, yojson, uuidm, stdint) is lean. Adding dependencies
  increases the chance of opam solver conflicts for users.

- **Existing CLI commands must not change.** The current interface is
  already used. This work is about packaging, not feature changes.

- **The library remains internal.** `kbases` has no `(public_name ...)`
  and should stay that way for this release. Exposing a library API is a
  separate, future decision.

- **Git repository requirement stays.** `bs` requires a git repo — this
  is a fundamental design choice, not a limitation to remove for launch.

## Resolved Research Questions

1. **Version number semantics in opam.** opam's solver uses Debian-style
   version ordering — no special treatment of `0.x` vs `1.x` (unlike
   npm's semver). There are no caret or tilde constraint operators. The
   choice is purely a social signal. Ecosystem precedent: cmdliner
   started at `0.9.0`, dune at `1.0.0`, ocamlformat at `0.9.1` (still
   0.x after 8 years). → Incorporated into requirement 5.

2. **CHANGES file format for `dune-release`.** `dune-release` auto-detects
   files named `changes` or `changelog` (case-insensitive, any
   extension). `CHANGES.md` is the dominant convention. The parser
   extracts the version from the first word of the first header.
   Keepachangelog sections (`### Added`, etc.) are supported since
   v1.6.0. → Incorporated into requirement 4.

3. **Windows support feasibility.** OCaml/opam 2.2+ supports Windows
   natively, but the ecosystem is overwhelmingly Unix-oriented. The
   production code's `Unix` usage is mostly portable, but the test
   infrastructure uses `Unix.fork`, `Unix.execve`, `Unix.kill`, and
   `/dev/null` — all broken on native Windows. Declaring
   `available: os != "win32"` is standard practice (Jane Street's `core`
   does the same). → Incorporated as requirement 6.

4. **Man page generation.** cmdliner generates man pages at runtime via
   `--help=groff`. cmdliner 2.x provides `cmdliner install
   tool-manpages` to extract and install them. Several tools (dune,
   cmarkit) ship man pages via opam. The effort is small (one dune rule
   in `bin/dune`), but `--help` is sufficient for an initial release.
   → Deferred; no requirement added. Can be revisited for a later
   release or when packaging for system package managers.

## Open Questions

### Requires discussion

1. **Pre-release feature scope.** The user mentioned features still
   missing for a 1.0. If the initial release is pre-1.0, which missing
   features should be called out in the README as planned, and which
   are better left unmentioned?
