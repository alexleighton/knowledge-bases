#!/usr/bin/env bash
set -euo pipefail

# Validates that the project builds from a clean environment by creating
# an isolated git worktree and fresh opam switch with the minimum declared
# OCaml compiler. Exits 0 on success, 1 on failure.
#
# Usage:
#   bash scripts/validate-build.sh [--keep] [--local] [--lower-bounds]
#
# --keep          Preserve the switch and worktree after the run (for debugging).
# --local         Copy dune-project and knowledge-bases.opam from the working
#                 tree into the worktree, allowing validation of uncommitted changes.
# --lower-bounds  After installing deps, downgrade each declared dependency to
#                 its lower-bound version before building and testing.

_parse_ocaml_version() {
  sed -n 's/.*(ocaml[[:space:]]*(>=[[:space:]]*"\([^"]*\)").*/\1/p' "$1"
}

# Parse declared dependencies from dune-project.
# Outputs lines of "pkg version" for each (pkg (>= "version")) entry,
# skipping dune, ocaml, and :with-dev-setup packages.
_parse_deps() {
  sed -n '/(depends/,/^[[:space:]]*)/p' "$1" \
    | grep -v ':with-dev-setup' \
    | grep -E '^\s*\([a-z]' \
    | grep -E '\(>=' \
    | sed -n 's/^[[:space:]]*(\([a-z0-9_-]*\)[[:space:]].*(>=[[:space:]]*"\([^"]*\)").*/\1 \2/p' \
    | grep -v -E '^(dune|ocaml) '
}

# Print resolved versions of declared dependencies.
_print_resolved_versions() {
  local dune_project="$1"
  echo ""
  echo "Resolved dependency versions:"
  while read -r pkg _constraint; do
    local installed
    installed="$(opam list --installed "$pkg" --columns=version -s 2>/dev/null || echo "not found")"
    printf "  %-20s %s\n" "$pkg" "$installed"
  done < <(_parse_deps "$dune_project")
  echo ""
}

_SWITCH_NAME=""
_WORKTREE_DIR=""

_cleanup() {
  opam switch remove "$_SWITCH_NAME" --yes 2>/dev/null || true
  git worktree remove "$_WORKTREE_DIR" --force 2>/dev/null || true
}

main() {
  local repo_root keep=false use_local=false lower_bounds=false
  repo_root="$(git rev-parse --show-toplevel)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep)         keep=true; shift ;;
      --local)        use_local=true; shift ;;
      --lower-bounds) lower_bounds=true; shift ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  local suffix
  suffix="$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  _SWITCH_NAME="kb-validate-$suffix"
  _WORKTREE_DIR="$(mktemp -d)"

  if [[ "$keep" == false ]]; then
    trap '_cleanup' EXIT
  else
    echo "--keep: will preserve switch '$_SWITCH_NAME' and worktree '$_WORKTREE_DIR'"
  fi

  echo "Creating worktree at $_WORKTREE_DIR..."
  git -C "$repo_root" worktree add "$_WORKTREE_DIR" HEAD --detach --quiet

  local dune_project="$_WORKTREE_DIR/dune-project"

  if [[ "$use_local" == true ]]; then
    echo "Copying working tree metadata into worktree (--local)..."
    cp "$repo_root/dune-project" "$dune_project"
    cp "$repo_root/knowledge-bases.opam" "$_WORKTREE_DIR/knowledge-bases.opam"
  fi

  local ocaml_version
  ocaml_version="$(_parse_ocaml_version "$dune_project")"

  if [[ -z "$ocaml_version" ]]; then
    echo "Error: could not parse OCaml version from dune-project" >&2
    exit 1
  fi

  echo "Updating package index..."
  opam update --quiet

  echo "Creating switch '$_SWITCH_NAME' with ocaml-base-compiler.$ocaml_version..."
  opam switch create "$_SWITCH_NAME" "ocaml-base-compiler.$ocaml_version"
  eval "$(opam env --switch="$_SWITCH_NAME" --set-switch)"

  echo "Installing dependencies..."
  cd "$_WORKTREE_DIR"
  opam install . --deps-only --with-test --yes

  _print_resolved_versions "$dune_project"

  if [[ "$lower_bounds" == true ]]; then
    echo "=== Lower-bound testing ==="
    echo "Downgrading each declared dependency to its lower-bound version..."
    echo ""

    local install_args=()
    while read -r pkg lower; do
      # Find the oldest available version that satisfies >= lower.
      # opam show --field=all-versions returns versions in ascending order.
      local all_versions oldest_match=""
      all_versions="$(opam show "$pkg" --field=all-versions 2>/dev/null)"
      for v in $all_versions; do
        local cmp
        cmp="$(opam admin compare-versions "$v" "$lower")"
        if [[ "$cmp" == *">"* || "$cmp" == *"="* ]]; then
          oldest_match="$v"
          break
        fi
      done

      if [[ -z "$oldest_match" ]]; then
        echo "  warning: no version of $pkg >= $lower found, skipping"
        continue
      fi

      local current
      current="$(opam list --installed "$pkg" --columns=version -s 2>/dev/null || echo "?")"
      if [[ "$current" == "$oldest_match" ]]; then
        printf "  %-20s %s (already at lower bound)\n" "$pkg" "$oldest_match"
      else
        printf "  %-20s %s -> %s\n" "$pkg" "$current" "$oldest_match"
        install_args+=("$pkg.$oldest_match")
      fi
    done < <(_parse_deps "$dune_project")

    echo ""
    if [[ ${#install_args[@]} -gt 0 ]]; then
      local failed=()
      for spec in "${install_args[@]}"; do
        echo "Installing $spec..."
        if ! opam install "$spec" --yes 2>&1; then
          echo "  FAILED: $spec is not installable in this switch"
          failed+=("$spec")
        fi
      done
      echo ""
      echo "Versions after downgrade:"
      _print_resolved_versions "$dune_project"
      if [[ ${#failed[@]} -gt 0 ]]; then
        echo "ERROR: could not install: ${failed[*]}"
        echo "These lower bounds are too low for the declared OCaml version."
        exit 1
      fi
    else
      echo "All dependencies already at their lower bounds."
    fi
  fi

  echo "Building..."
  dune build

  echo "Running tests..."
  dune runtest

  echo ""
  echo "Validation passed."
}

main "$@"
