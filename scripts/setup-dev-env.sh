#!/usr/bin/env bash
set -euo pipefail

# Creates (or updates) a named opam switch for this project with the
# correct OCaml compiler and all dependencies installed.

SWITCH_NAME="knowledge-bases"

_parse_ocaml_version() {
  sed -n 's/.*(ocaml[[:space:]]*(>=[[:space:]]*"\([^"]*\)").*/\1/p' "$1"
}

main() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"

  local ocaml_version
  ocaml_version="$(_parse_ocaml_version "$repo_root/dune-project")"

  if [[ -z "$ocaml_version" ]]; then
    echo "Error: could not parse OCaml version from dune-project" >&2
    exit 1
  fi

  if opam switch list --short | grep -qx "$SWITCH_NAME"; then
    echo "Switch '$SWITCH_NAME' already exists. Updating dependencies..."
  else
    echo "Creating switch '$SWITCH_NAME' with ocaml-base-compiler.$ocaml_version..."
    opam switch create "$SWITCH_NAME" "ocaml-base-compiler.$ocaml_version"
  fi

  eval "$(opam env --switch="$SWITCH_NAME" --set-switch)"
  opam install "$repo_root" --deps-only --with-test --with-dev-setup --yes

  # Link the switch to the repo root so opam auto-activates it in this
  # directory tree (requires the opam shell hook or eval $(opam env)).
  echo "Linking switch '$SWITCH_NAME' to $repo_root..."
  opam switch link "$SWITCH_NAME" "$repo_root"

  echo "Done. The switch activates automatically in $repo_root via opam shell hook."
}

main "$@"
