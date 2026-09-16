#!/usr/bin/env bash
# Scenario 3: run the installer twice.
#
# Expected: the second run changes nothing -- no duplicated rc lines, no new
# backups, and the same Neovim.

# shellcheck source=test/install/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

echo "== first run =="
bash "${REPO}/scripts/setup.sh" --no-fonts >/dev/null

BASHRC_BEFORE="$(md5sum "$HOME/.bashrc" | cut -d' ' -f1)"
LINK_BEFORE="$(readlink "$HOME/.config/nvim")"
NVIM_BEFORE="$(readlink "$HOME/.local/bin/nvim")"
BACKUPS_BEFORE="$(find "$HOME" -maxdepth 4 -name '*.bak.*' 2>/dev/null | sort)"
LOCK_BEFORE="$(md5sum "${REPO}/nvim/lazy-lock.json" | cut -d' ' -f1)"

echo
echo "== second run =="
bash "${REPO}/scripts/setup.sh" --no-fonts >/dev/null

echo
echo "== assertions =="
assert_eq "$(md5sum "$HOME/.bashrc" | cut -d' ' -f1)" "$BASHRC_BEFORE" "path ~/.bashrc is byte-identical"
assert_count "$HOME/.bashrc" "shell/env.sh" 1 "the env line appears exactly once"
assert_eq "$(readlink "$HOME/.config/nvim")" "$LINK_BEFORE" "path ~/.config/nvim still points at the same place"
assert_eq "$(readlink "$HOME/.local/bin/nvim")" "$NVIM_BEFORE" "the nvim symlink is unchanged"
assert_eq "$(find "$HOME" -maxdepth 4 -name '*.bak.*' 2>/dev/null | sort)" "$BACKUPS_BEFORE" "no new backups were made"
assert_eq "$(md5sum "${REPO}/nvim/lazy-lock.json" | cut -d' ' -f1)" "$LOCK_BEFORE" "lazy-lock.json was restored, not rewritten"

finish
