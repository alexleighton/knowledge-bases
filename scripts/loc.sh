#!/usr/bin/env bash
set -euo pipefail

# Counts lines of code in the project source directories.
# Usage: scripts/loc.sh [--total]

dirs=(bin lib test test-integration)
root="$(cd "$(dirname "$0")/.." && pwd)"

total=0
show_breakdown=true

if [[ "${1:-}" == "--total" ]]; then
  show_breakdown=false
fi

for dir in "${dirs[@]}"; do
  count=$(find "$root/$dir" -type f \( -name '*.ml' -o -name '*.mli' \) -print0 \
    | xargs -0 cat 2>/dev/null | wc -l | tr -d ' ')
  total=$((total + count))
  if $show_breakdown; then
    printf "%-20s %s\n" "$dir" "$count"
  fi
done

if $show_breakdown; then
  printf "%-20s %s\n" "total" "$total"
else
  echo "$total"
fi
