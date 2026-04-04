# `test-integration/` Principles

Guiding principles for code that lives in `test-integration/`.

## 1. Low nesting depth

Keep expressions nested at most two or three levels deep. Deeply nested code
is hard to follow because the reader must hold every enclosing context in their
head at once. When nesting grows, treat it as a signal that the code should be
restructured.

Approaches for reducing nesting:

* **Use monadic result operators (`let*`, `let+`).** Replace manual
  `match … with Ok x -> … | Error e -> Error e` chains with `Result.Syntax`
  bind operators so each step in a result pipeline sits at the same
  indentation level.

* **Extract resource-management wrappers.** When code follows a
  setup/use/cleanup pattern (transactions, file handles, temporary state),
  capture the bracketing in a higher-order function that takes the body as a
  callback.

* **Consolidate error mapping into named functions.** Instead of matching on
  error variants inline at every call site, define a reusable mapping function
  and apply it with `Result.map_error` in a pipeline.

* **Factor repeated control-flow shapes into helpers.** When the same nesting
  structure repeats across call sites or tests — e.g., acquire a resource,
  match on the result, use it, clean up — give that shape a name.

* **Unwrap setup results that must succeed.** When a test setup step (e.g.,
  initialising a repository) is expected to always succeed, use an unwrap
  helper that fails on error rather than nesting the entire test body inside
  a `match` arm.

## 2. Clean up temporary files and directories

Tests that create temporary directories must remove them when the test
finishes — including when the test fails or raises an exception. Use
`with_git_root` from `test_helper.ml` rather than creating directories
manually. It brackets the test body with `Fun.protect` and cleans up
automatically.

**Why:** Leaked temp directories accumulate across test runs and CI builds,
wasting disk space and making it harder to diagnose failures.

## 3. File length

Keep test files under ~300 lines. When a file outgrows this threshold, split it
by feature area.

**Naming:** `<command>_<aspect>_expect.ml` — the command prefix stays the same
and an aspect suffix is added. For example, `show_expect.ml` might split into
`show_basic_expect.ml`, `show_relations_expect.ml`, `show_json_expect.ml`.
Remove the original unsuffixed file so there is no ambiguity about which file is
"primary."

**Discovery:** glob `<command>_*_expect.ml` to find all test files for a
command.

**Preamble duplication:** each split file duplicates the preamble (typically just
`module Helper = Test_helper`). Shared logic belongs in `test_helper.ml`, not
copied between files.

## 4. Descriptive test names

Every `let%expect_test` name must describe the behaviour being verified, not the
function being called. A reader should know what the test checks without opening
the file.

* **Bad:** `"make comprehensive test"`, `"happy path"`, `"error cases"`
* **Good:** `"make succeeds with valid inputs and rejects wrong TypeId prefix"`,
  `"list filters by status"`, `"delete returns Not_found for missing niceid"`

When a single test exercises both success and failure paths, mention both in the
name. Prefer the pattern `"<function> <what it does under these conditions>"`.

**Why:** Vague names force the reader to scan the test body to understand intent.
When a test fails in CI, the name is the first thing you see — it should tell you
what broke without further investigation.

## 5. Avoid boolean-printing assertions

Do not wrap a predicate check in `Printf.printf "%b"` as the sole assertion.
When the check fails the output is just `false` with no indication of what the
actual value was.

```ocaml
(* avoid *)
Printf.printf "is-dir-error: %b\n"
  (String.starts_with ~prefix:"Directory is not a git repository" msg)

(* prefer — success prints a stable label, failure prints the actual value *)
if String.starts_with ~prefix:"Directory is not a git repository" msg
then print_endline "is-dir-error: true"
else Printf.printf "unexpected validation error: %s\n" msg
```

The `if/else` form gives the same deterministic expected output on success but
surfaces the real message on failure, making debugging straightforward.

**Why:** A bare `false` in a failed expect-test diff tells you the predicate
didn't hold but not *why*. Printing the actual value on the failure branch
eliminates a re-run-with-logging step.

## 6. Reduce entity construction boilerplate

When many tests in a file build the same entity type with mostly default fields,
define a local builder helper with optional parameters:

```ocaml
let make_note
    ?(status = Note.Active)
    ?(created_at = 0) ?(updated_at = 0)
    tid niceid title content =
  Note.make tid (Id.from_string niceid)
    (Title.make title) (Content.make content) status
    ~created_at:(Timestamp.make created_at)
    ~updated_at:(Timestamp.make updated_at)
```

Call sites then only mention the fields that matter for the test:

```ocaml
let note = make_note tid "test-1" "Title" "Body" in
let archived = make_note ~status:Note.Archived tid "test-2" "Title" "Body" in
let timed = make_note ~created_at:1000 ~updated_at:2000 tid "test-3" "Title" "Body" in
```

Keep the builder local to the test file (not in shared helpers) — different
files test different modules and need differently shaped builders.

**Why:** Repeating `~created_at:(Timestamp.make 0) ~updated_at:(Timestamp.make
0)` on every construction call obscures the parameters that actually vary between
tests. A builder makes the interesting inputs stand out.
