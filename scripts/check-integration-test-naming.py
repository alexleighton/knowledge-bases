#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# ///
"""Check that integration test filenames match CLI commands.

Convention: a test file at test-integration/<stem>_expect.ml must
correspond to a CLI command.  The stem is either a command name
(e.g. show_expect.ml -> `bs show`) or a command name followed by an
aspect suffix (e.g. show_json_expect.ml -> `bs show`, aspect "json").

For nested subcommands, path segments are joined with underscores
(e.g. `bs add note` -> add_note_expect.ml).

Aspect suffixes are only valid when a command has been split across
multiple test files.  A lone file for a command must use the plain
<command>_expect.ml name.

workflow_*_expect.ml files are exempt — they test cross-command
scenarios and intentionally cut across the per-command boundary.

Files that don't follow the *_expect.ml pattern are silently skipped
(e.g. test_helper.ml).

Command names are derived from bin/cmd_*.ml files, with a special
case for group commands (like `add`) whose subcommands are specified
in SUBCOMMANDS below.

Usage:
    ./scripts/check-integration-test-naming.py       # check all
    ./scripts/check-integration-test-naming.py -v    # verbose logging
"""

import argparse
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST_DIR = ROOT / "test-integration"
BIN_DIR = ROOT / "bin"

VERBOSE = False

EXPECT_SUFFIX = "_expect.ml"

# Stems exempt from the cmd_*.ml matching rule.  Prefix match: "workflow"
# exempts workflow_planning_expect.ml, workflow_persistence_expect.ml, etc.
# "help" exempts help_expect.ml (tests the top-level command, no cmd_help.ml).
EXEMPT_PREFIXES = ["workflow", "help"]

# Group commands whose subcommands are the real test targets.
# Maps the group name to its list of subcommand names.
# The joined form (e.g. "add_note") becomes a valid command stem.
SUBCOMMANDS = {
    "add": ["note", "todo"],
}


def log(msg):
    if VERBOSE:
        print(f"  [verbose] {msg}", file=sys.stderr)


def discover_commands():
    """Build the set of valid command stems from bin/cmd_*.ml files."""
    commands: set[str] = set()
    for p in BIN_DIR.iterdir():
        if not p.name.startswith("cmd_") or p.suffix != ".ml":
            continue
        name = p.stem.removeprefix("cmd_")
        if name in SUBCOMMANDS:
            for sub in SUBCOMMANDS[name]:
                commands.add(f"{name}_{sub}")
        else:
            commands.add(name)
    return commands


def check():
    commands = discover_commands()
    log(f"commands = {sorted(commands)}")

    errors: list[str] = []
    file_count = 0

    if not TEST_DIR.is_dir():
        log("test-integration/ does not exist, nothing to check")
        return errors, 0

    # First pass: resolve each test file to its command.
    # command -> list of (filename, aspect_or_None)
    command_files: dict[str, list[tuple[str, str | None]]] = defaultdict(list)
    unresolved: list[tuple[str, str]] = []

    for test_file in sorted(TEST_DIR.iterdir()):
        if not test_file.name.endswith(EXPECT_SUFFIX):
            continue

        file_count += 1
        stem = test_file.name.removesuffix(EXPECT_SUFFIX)

        # Exempt prefixes (workflow_*, help, etc.).
        if any(stem.startswith(p) for p in EXEMPT_PREFIXES):
            log(f"  {test_file.name} -> {stem} (exempt)")
            continue

        # Exact match: stem is the command name.
        if stem in commands:
            log(f"  {test_file.name} -> {stem} (exact)")
            command_files[stem].append((test_file.name, None))
            continue

        # Aspect match: stem is <command>_<aspect>.
        # Try progressively shorter prefixes (longest match wins).
        parts = stem.split("_")
        found = False
        for i in range(len(parts) - 1, 0, -1):
            candidate = "_".join(parts[:i])
            if candidate in commands:
                aspect = "_".join(parts[i:])
                log(f"  {test_file.name} -> {candidate} (aspect: {aspect})")
                command_files[candidate].append((test_file.name, aspect))
                found = True
                break

        if not found:
            log(f"  {test_file.name} -> UNRESOLVED")
            unresolved.append((test_file.name, stem))

    # Report files that don't match any command.
    for filename, stem in unresolved:
        errors.append(
            f"test-integration/{filename}: "
            f"no CLI command matching '{stem}'"
        )

    # Second pass: lone aspect check.
    for command, files in command_files.items():
        if len(files) == 1:
            filename, aspect = files[0]
            if aspect is not None:
                errors.append(
                    f"test-integration/{filename}: "
                    f"aspect suffix '{aspect}' on sole test file for "
                    f"'{command}' — rename to {command}{EXPECT_SUFFIX}"
                )

    return errors, file_count


def main():
    global VERBOSE
    name = "check-integration-test-naming.py"
    parser = argparse.ArgumentParser(
        description="Check that integration test filenames match CLI commands."
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
