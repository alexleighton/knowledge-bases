#!/usr/bin/env bash
set -euo pipefail

# Installs a git pre-push hook that runs the test suite (dune runtest).
# If tests fail, the push is blocked. If they pass, the push continues.

main() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"

  local hook_path="$repo_root/.git/hooks/pre-push"

  cat >"$hook_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

border="*~*~*~*~*~*~*~*~*~*~*~*~*~*~*"

echo "$border"
echo "🧪 Kicking off tests (dune runtest)..."
if dune runtest; then
  echo "✅ Tests passed. Proceeding with push."
  echo "$border"
  exit 0
else
  echo "❌ Tests failed. Push aborted."
  echo "$border"
  exit 1
fi
EOF

  chmod +x "$hook_path"
  echo "Installed pre-push hook at $hook_path"
}

main "$@"
