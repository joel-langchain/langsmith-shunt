# Assertion helpers shared by the test scripts.
# shellcheck disable=SC2034  # ROOT and SHUNT are used by the sourcing scripts

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHUNT="$ROOT/plugins/langsmith-shunt"
passed=0
failed=0

pass() {
  passed=$((passed + 1))
  printf '  ok    %s\n' "$1"
}

fail() {
  failed=$((failed + 1))
  printf '  FAIL  %s\n' "$1"
  [ -n "${2:-}" ] && printf '        %s\n' "$2"
}

# assert <name> <condition command...>
assert() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name" "failed: $*"; fi
}

contains() { grep -qF -- "$2" "$1"; }
not_contains() { ! grep -qF -- "$2" "$1"; }

summary() {
  printf '\n%d passed, %d failed\n' "$passed" "$failed"
  [ "$failed" -eq 0 ]
}
