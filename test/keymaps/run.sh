#!/usr/bin/env bash
#
# Keymap test runner.
#
#   test/keymaps/run.sh            # mappings only, no plugins  (fast)
#   test/keymaps/run.sh --full     # the same spec against the real LazyVim config
#
# Exits non-zero when any assertion fails.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
NVIM="${NVIM:-nvim}"

MODE="minimal"
[ "${1:-}" = "--full" ] && MODE="full"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/nvim-keymap-test.XXXXXX")"
SOCKET="${TMP}/nvim.sock"
SERVER_PID=""

# shellcheck disable=SC2329  # invoked through the EXIT trap
cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

if [ "$MODE" = "full" ]; then
  # Run against the real configuration, but in a throwaway XDG environment so
  # the developer's own ~/.config and ~/.local are never read or written.
  export XDG_CONFIG_HOME="${TMP}/config"
  export XDG_DATA_HOME="${TMP}/data"
  export XDG_STATE_HOME="${TMP}/state"
  export XDG_CACHE_HOME="${TMP}/cache"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
  # A copy, not a symlink: lazy.nvim writes lazy-lock.json into stdpath("config")
  # whenever it installs something, and a test run must not touch the repo.
  cp -R "${ROOT}/nvim" "${XDG_CONFIG_HOME}/nvim"

  if [ -n "${NVIM_TEST_SHARE_DATA:-}" ] && [ -d "$NVIM_TEST_SHARE_DATA" ]; then
    # Reuse an already-populated plugin directory instead of cloning everything
    # again (CI sets this after the installer run).
    rm -rf "$XDG_DATA_HOME"
    ln -s "$NVIM_TEST_SHARE_DATA" "$XDG_DATA_HOME"
  fi

  echo "==> starting Neovim with the full LazyVim config (this installs plugins on first run)"
  "$NVIM" --headless --listen "$SOCKET" -u "${XDG_CONFIG_HOME}/nvim/init.lua" \
    -c "source ${HERE}/full-init.lua" >"${TMP}/server.log" 2>&1 &
  SERVER_PID=$!
else
  echo "==> starting Neovim with config/vscode.lua only"
  "$NVIM" --headless --clean --listen "$SOCKET" -u "${HERE}/init.lua" \
    >"${TMP}/server.log" 2>&1 &
  SERVER_PID=$!
fi

# Wait for the server to come up.
tries=0
until [ -S "$SOCKET" ]; do
  tries=$((tries + 1))
  if [ "$tries" -gt 600 ]; then
    echo "ERROR: Neovim never created $SOCKET" >&2
    sed 's/^/    /' "${TMP}/server.log" >&2
    exit 1
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: the Neovim server exited before it was ready" >&2
    sed 's/^/    /' "${TMP}/server.log" >&2
    exit 1
  fi
  perl -e 'select(undef, undef, undef, 0.25)' 2>/dev/null || sleep 1
done

set +e
"$NVIM" --clean -l "${HERE}/spec.lua" "$SOCKET" "$TMP"
status=$?
set -e

if [ -s "${TMP}/server.log" ]; then
  echo "--- server log ---"
  sed 's/^/    /' "${TMP}/server.log"
fi

exit "$status"
