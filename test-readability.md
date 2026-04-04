# Test Readability Improvements

Suggestions from a review of `test/`, with status.

## 1. Vague test names

Names like `"make comprehensive test"` and `"happy path"` don't describe what's
being verified. Renamed to e.g. `"make succeeds with valid inputs and rejects
wrong TypeId prefix"`.

**Status:** Done. Principle added to `docs/test/principles.md` (§7) and
`docs/test-integration/principles.md` (§4).

## 2. Near-identical Note/Todo test pairs

The repository and data test files for Note and Todo are structurally identical
--- same test names, same patterns, only the module and status values differ.

**Status:** Acknowledged. The duplication is a consequence of the expect-test
format (literal expected output resists abstraction). Acceptable trade-off.

## 3. Monolithic CRUD tests

The `"create/get/update/delete happy path"` tests in
`repository/{note,todo}_expect.ml` exercised four operations in sequence. If
`create` broke, the failure pointed at the whole block.

**Status:** Done. Split into four focused tests per file: `create assigns niceid
and persists row`, `get and get_by_niceid return created ...`, `update changes
persisted fields`, `delete removes ... and get_by_niceid returns Not_found`.

## 4. Exhaustive error-variant matches add noise

Match sites that only care about one variant enumerated all others with
throwaway labels like `"unexpected duplicate"`. Replaced with a catch-all
`| Error err -> pp_error err` that delegates to an exhaustive printer ---
less noise, same safety, and better debugging output.

**Status:** Done. Triggers warning 4 (fragile-match); suppressed in `test/dune`
with a comment explaining the rationale.

## 5. Entity construction boilerplate

Most data-layer tests repeated
`~created_at:(Timestamp.make 0) ~updated_at:(Timestamp.make 0)` on every
`Note.make` / `Todo.make` call. Added local `make_note` / `make_todo` builders
with optional parameters so call sites only mention what varies.

**Status:** Done. Principle added to `docs/test/principles.md` (§9) and
`docs/test-integration/principles.md` (§6).

## 6. Boolean-printing assertions obscure intent

`Printf.printf "is-dir-error: %b\n" (String.starts_with ...)` prints `false`
on failure with no context. Replaced with an `if/then/else` that prints a stable
label on success and the actual value on failure.

**Status:** Done (lifecycle_init_expect.ml). Principle added to
`docs/test/principles.md` (§8) and `docs/test-integration/principles.md` (§5).

## 7. Helper alias blocks add indirection

Service test files rebinding 5--9 names from `Test_helpers` one by one. Replaced
with `open Test_helpers`; only renamed aliases (e.g. `let pp_error =
pp_item_error`) remain as explicit bindings. Redundant `module TodoRepo` /
`module NoteRepo` aliases removed where they duplicated what the open provides.

**Status:** Done across 21 service test files.

## 8. `unwrap_*` functions swallow error details

Repository test `unwrap_note` / `unwrap_todo` caught `Error _` and raised
`failwith "unexpected error"`. Expanded to print the actual error variant and
its payload.

**Status:** Done.
