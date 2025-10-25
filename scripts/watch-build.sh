#!/bin/bash
#
# Usage:
#   ./scripts/watch-build.sh
#
# This script will rebuild and run tests when files change.
#
# The --force flag is used to force a full rebuild of the project.
# The --watch flag is used to watch for changes to files known-to-dune.
# The --terminal-persistence=clear-on-rebuild flag clears the terminal for each rebuild.

dune runtest --force --watch --terminal-persistence=clear-on-rebuild