#!/usr/bin/env bash
# Scenario 2: Ubuntu's own neovim package (too old for LazyVim) is installed.
#
# Expected: the installer refuses, explains why, and -- the point of the whole
# preflight design -- leaves the machine byte for byte as it found it.

# shellcheck source=test/install/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

echo "== installing the distro's neovim =="
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq neovim
nvim --version | head -n1

BASHRC_BEFORE="$(md5sum "$HOME/.bashrc" | cut -d' ' -f1)"

echo
echo "== running the installer (it must fail) =="
set +e
OUTPUT="$(bash "${REPO}/scripts/setup.sh" --no-fonts 2>&1)"
STATUS=$?
set -e
printf '%s\n' "$OUTPUT" | sed 's/^/    /'

echo
echo "== assertions =="
if [ "$STATUS" -ne 0 ]; then pass "the installer exited non-zero"; else fail "the installer should have failed"; fi

case "$OUTPUT" in
  *"Neovim is too old"*) pass "the error names the problem" ;;
  *) fail "the error message does not say Neovim is too old" ;;
esac
case "$OUTPUT" in
  *"Nothing has been changed on your system."*) pass "the error promises nothing changed" ;;
  *) fail "the error is missing the 'Nothing has been changed' sentence" ;;
esac
case "$OUTPUT" in
  *"/usr/bin/nvim"*) pass "the error names the offending path" ;;
  *) fail "the error does not name the detected nvim path" ;;
esac
case "$OUTPUT" in
  *"apt-get remove"*) pass "the error gives an apt-specific upgrade hint" ;;
  *) fail "the error does not give the apt hint" ;;
esac
case "$OUTPUT" in
  *">= 0.11.2"*) pass "the error states the required version" ;;
  *) fail "the error does not state the required version" ;;
esac

echo
echo "== nothing was touched =="
assert_absent "$HOME/.config/nvim" "path ~/.config/nvim was not created"
assert_absent "$HOME/.local/share/nvim" "path ~/.local/share/nvim was not created"
assert_absent "$HOME/.local/state/nvim" "path ~/.local/state/nvim was not created"
assert_absent "$HOME/.local/share/nvim-dist" "no Neovim was installed"
assert_absent "$HOME/.local/bin/nvim" "no managed nvim symlink"
assert_eq "$(md5sum "$HOME/.bashrc" | cut -d' ' -f1)" "$BASHRC_BEFORE" "path ~/.bashrc is unchanged"

finish
