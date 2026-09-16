#!/usr/bin/env bash
# Scenario 1: a clean Ubuntu 24.04 that has nothing but curl and sudo.
#
# Expected: Neovim is installed into ~/.local, the config is linked, and
# :checkhealth reports no ERROR for the components this repo is responsible for.

# shellcheck source=test/install/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

echo "== running the installer =="
bash "${REPO}/scripts/setup.sh" --no-fonts

echo
echo "== assertions =="
assert_exists "$HOME/.local/share/nvim-dist" "Neovim was installed into ~/.local/share/nvim-dist"
assert_exists "$HOME/.local/bin/nvim" "the managed nvim symlink exists"
assert_symlink_to "$HOME/.config/nvim" "${REPO}/nvim" "path ~/.config/nvim points at the repo"
assert_contains "$HOME/.bashrc" "shell/env.sh" "path ~/.bashrc sources shell/env.sh"
assert_exists "$HOME/.local/bin/fd" "fd shim for Debian's fdfind"

NVIM="$HOME/.local/bin/nvim"
assert_eq "$("$NVIM" --version | head -n1 | sed 's/^NVIM v//' | cut -d. -f1-2)" "0.12" "the installed Neovim is 0.12.x"

echo
echo "== headless load of the real config =="
if COLORTERM=truecolor "$NVIM" --headless -c "luafile ${REPO}/test/verify-config.lua"; then
  pass "LazyVim loads, the colourscheme resolves and the mappings are live"
else
  fail "test/verify-config.lua reported a problem"
fi

echo
echo "== checkhealth =="
REPORT="$(mktemp)"
"$NVIM" --headless -c 'checkhealth lazy vim.lsp vim.provider nvim-treesitter mason' \
  -c "w! ${REPORT}" -c 'qa!' >/dev/null 2>&1 || true

# Only our own components matter here: a container has no clipboard, no python
# provider and no perl, and Neovim reports all three as warnings or errors that
# say nothing about this repo.
if grep -E '^\s*- ERROR' "$REPORT" | grep -viE 'clipboard|python|perl|ruby|node .* provider'; then
  fail "checkhealth reported an error for one of our components"
else
  pass "checkhealth is clean for lazy.nvim, mason, treesitter and LSP"
fi
rm -f "$REPORT"

finish
