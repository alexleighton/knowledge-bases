# Knowledge Bases

Repository-local issue and note tracker.

## Building

* Full compilation: `dune build`
* Run tests: `dune runtest`
* Run checks (unused code, etc.): `dune build @runcheck`
* Run `dune` commands sequentially (not in parallel): `dune` uses a shared build
  lock, so concurrent `build`/`exec`/`runtest` commands can fail.

## Main Executable

`dune exec bs`

## Library Sources

OCaml source (`.ml`/`.mli`) for installed dependencies is available under
`~/.opam/default/lib/<package>/`. Read these files to understand library APIs
when documentation is insufficient.

## Additional Documentation

All documentation related to coding principles and practices, project
conventions, etc can be discovered via the index: `docs/index.md`.
Do not use the auto memory system; project context is managed here instead.

## Knowledge Base

This repository uses `bs` to track todos and notes. Use it to
externalize work you've identified, decisions, and research.

```
# Create items (content from stdin)
echo "Description" | bs add todo "Title"
echo "Research findings" | bs add note "Title"

# Browse
bs list
bs list --available
bs show kb-0

# Claim and work on todos
bs next --show
bs claim kb-0

# Complete and archive
bs resolve kb-0 kb-1
bs archive kb-5 kb-6
```

Run `bs --help` for the full command reference.
