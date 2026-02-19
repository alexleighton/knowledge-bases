# Knowledge Bases

Repository-local issue and note tracker.

## Building

* Full compilation: `dune build`
* Run tests: `dune runtest`
* Run `dune` commands sequentially (not in parallel): `dune` uses a shared build
  lock, so concurrent `build`/`exec`/`runtest` commands can fail.

## Main Executable

`dune exec bs`

## Additional Documentation

All documentation related to coding principles and practices, project
conventions, etc can be discovered via the index: `docs/index.md`.
