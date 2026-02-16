# `bin/` Principles

Guiding principles for code that lives in `bin/`.

## 1. No unit tests for `bin/`

Code in `bin/` is **not** unit tested. It should contain only:

- Command-line argument definitions and parsing (Cmdliner terms and commands).
- Thin orchestration that wires CLI inputs to `lib/` services.

Any logic beyond that — validation, resolution, business rules — belongs in
`lib/` where it can be covered by unit tests. If you find yourself wanting to
test something in `bin/`, that is a signal the logic should move into a module
under `lib/`.
