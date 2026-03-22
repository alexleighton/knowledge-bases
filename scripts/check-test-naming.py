#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# ///
"""Check that unit test filenames match the modules they exercise.

Convention: a test file at test/<layer>/<stem>_expect.ml must correspond
to a source module in lib/<layer>/.  The stem is either the module name
itself (e.g. note_expect.ml -> note.ml) or a module name followed by an
aspect suffix (e.g. mutation_service_claim_expect.ml ->
mutation_service.ml, aspect "claim").

Aspect suffixes are only valid when a module has been split across
multiple test files.  A lone file for a module must use the plain
<module>_expect.ml name — a single-file aspect like
note_repo_expect.ml (where no other note_*_expect.ml exists) means
the filename is misleading.

Files that don't follow the *_expect.ml pattern are silently skipped
(e.g. test_helpers.ml).

Usage:
    ./scripts/check-test-naming.py          # check all unit tests
    ./scripts/check-test-naming.py -v       # verbose logging
"""

import argparse
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST_DIR = ROOT / "test"
LIB_DIR = ROOT / "lib"

VERBOSE = False

# Layers where the rule applies — maps test/ subdirectory to lib/ subdirectory.
LAYERS = {
    "control": "control",
    "data": "data",
    "data/uuid": "data/uuid",
    "repository": "repository",
    "service": "service",
}

EXPECT_SUFFIX = "_expect.ml"


def log(msg):
    if VERBOSE:
        print(f"  [verbose] {msg}", file=sys.stderr)


def check():
    errors: list[str] = []
    file_count = 0

    for test_layer, lib_layer in LAYERS.items():
        test_path = TEST_DIR / test_layer
        lib_path = LIB_DIR / lib_layer

        if not test_path.is_dir():
            log(f"skip {test_layer}: test directory does not exist")
            continue

        # Collect the set of module stems available in the lib layer.
        lib_modules = {
            p.stem for p in lib_path.iterdir() if p.suffix == ".ml"
        }
        log(f"{test_layer}: lib modules = {sorted(lib_modules)}")

        # First pass: resolve each test file to its module (or record an error).
        # module_name -> list of (filename, aspect_or_None)
        module_files: dict[str, list[tuple[str, str | None]]] = defaultdict(list)
        unresolved: list[tuple[str, str]] = []

        for test_file in sorted(test_path.iterdir()):
            if not test_file.name.endswith(EXPECT_SUFFIX):
                continue

            file_count += 1
            stem = test_file.name.removesuffix(EXPECT_SUFFIX)

            # Exact match: stem is the module name.
            if stem in lib_modules:
                log(f"  {test_file.name} -> {stem} (exact)")
                module_files[stem].append((test_file.name, None))
                continue

            # Aspect match: stem is <module>_<aspect>.
            # Try progressively shorter prefixes (longest module match wins).
            parts = stem.split("_")
            found = False
            for i in range(len(parts) - 1, 0, -1):
                candidate = "_".join(parts[:i])
                if candidate in lib_modules:
                    aspect = "_".join(parts[i:])
                    log(f"  {test_file.name} -> {candidate} (aspect: {aspect})")
                    module_files[candidate].append((test_file.name, aspect))
                    found = True
                    break

            if not found:
                log(f"  {test_file.name} -> UNRESOLVED")
                unresolved.append((test_file.name, stem))

        # Report files that don't match any module.
        for filename, stem in unresolved:
            errors.append(
                f"test/{test_layer}/{filename}: "
                f"no module matching '{stem}' in lib/{lib_layer}/"
            )

        # Second pass: check that aspect suffixes only appear when there are
        # multiple files for that module.
        for module, files in module_files.items():
            if len(files) == 1:
                filename, aspect = files[0]
                if aspect is not None:
                    errors.append(
                        f"test/{test_layer}/{filename}: "
                        f"aspect suffix '{aspect}' on sole test file for "
                        f"'{module}' — rename to {module}{EXPECT_SUFFIX}"
                    )

    return errors, file_count


def main():
    global VERBOSE
    name = "check-test-naming.py"
    parser = argparse.ArgumentParser(
        description="Check that unit test filenames match source modules."
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Print detailed resolution info to stderr."
    )
    args = parser.parse_args()
    VERBOSE = args.verbose

    errors, file_count = check()

    if errors:
        print(f"{name}: FAIL", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        sys.exit(1)
    else:
        print(f"{name}: ok ({file_count} files)", file=sys.stderr)
        sys.exit(0)


if __name__ == "__main__":
    main()
