#!/usr/bin/env bash
# Assertions shared by the installer scenarios. Sourced inside the container.

set -euo pipefail

REPO="${REPO:-$HOME/nvim-config}"
FAILED=0

pass() { printf '  PASS  %s\n' "$*"; }
fail() {
  printf '  FAIL  %s\n' "$*" >&2
  FAILED=1
}

assert_exists() {
  if [ -e "$1" ] || [ -L "$1" ]; then pass "$2"; else fail "$2 (missing: $1)"; fi
}

assert_absent() {
  if [ -e "$1" ] || [ -L "$1" ]; then fail "$2 (unexpectedly present: $1)"; else pass "$2"; fi
}

assert_symlink_to() {
  local actual
  actual="$(readlink "$1" 2>/dev/null || true)"
  if [ "$actual" = "$2" ]; then pass "$3"; else fail "$3 ($1 -> ${actual:-nothing}, expected $2)"; fi
}

assert_contains() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3 (not found in $1: $2)"; fi
}

assert_count() {
  local n
  n="$(grep -cF -- "$2" "$1" 2>/dev/null || true)"
  if [ "${n:-0}" -eq "$3" ]; then pass "$4"; else fail "$4 (found ${n:-0} of '$2' in $1, expected $3)"; fi
}

assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1', expected '$2')"; fi
}

finish() {
  if [ "$FAILED" -eq 0 ]; then
    printf '\n  scenario passed\n'
    exit 0
  fi
  printf '\n  scenario FAILED\n' >&2
  exit 1
}
