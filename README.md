# Knowledge Bases

A CLI tool for creating and managing git-distributed knowledge bases suited for coding agents.

# Features

No features right now.

MVP Featureset to be built:

  * Stable "database" file which can be clearly `diff`'d by git.
  * Structured issues, uniquely identified, and capable of being related to eachother. These will represent agent-determined TODOs, tracked externally from the agent's context, to free up space in context and keep the agent's attention focused.
  * Structured notes, uniquely identified, for capturing research, ideas, and decisions.
  * opam-distributed binary, let's say `bs`, for basic issue and note management.
    * E.g. `bs init`, `bs list`, `bs show`, `bs create`, `bs update`, `bs resolve`.

# Development

**Prerequisites** (install separately):

* [opam](https://opam.ocaml.org/doc/Install.html) — OCaml package manager
* [shellcheck](https://www.shellcheck.net/) — shell script linter
* [uv](https://docs.astral.sh/uv/) — Python script runner (used by `scripts/check-unused.py`)

**Environment Setup:**

```
$ bash scripts/setup-dev-env.sh
$ eval $(opam env --switch=knowledge-bases)
```

This creates a named opam switch with the correct OCaml compiler
and all dependencies. Run it once after cloning. If dependencies
change, re-run the setup script to update.

**Build:**

```
$ dune build
```

**Invoke Executable:**

```
$ dune exec bs
```

**Tests (expect tests):**

```
$ dune runtest
# If outputs changed and you want to accept them:
$ dune promote
```

**Git hooks:**

```
$ bash scripts/install-pre-push-hook.sh
# Installs a pre-push hook that runs dune runtest before pushes
```

# License

This project is licensed under the terms of the MIT license. See LICENSE.txt
