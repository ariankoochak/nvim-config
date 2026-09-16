#!/usr/bin/env bash
# Scenario 4: a Neovim newer than the minimum is already installed.
#
# Expected: it is used as-is. No second Neovim is downloaded, and nothing lands
# in ~/.local/share/nvim-dist.

# shellcheck source=test/install/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

PREINSTALLED_VERSION="${PREINSTALLED_NVIM_VERSION:-v0.12.5}"

echo "== installing Neovim ${PREINSTALLED_VERSION} into /usr/local =="
arch="$(uname -m)"
case "$arch" in
  x86_64) asset="nvim-linux-x86_64" ;;
  aarch64 | arm64) asset="nvim-linux-arm64" ;;
  *)
    echo "unsupported arch $arch" >&2
    exit 1
    ;;
esac
curl -fsSL "https://github.com/neovim/neovim/releases/download/${PREINSTALLED_VERSION}/${asset}.tar.gz" -o /tmp/nvim.tar.gz
sudo tar -xzf /tmp/nvim.tar.gz -C /opt
sudo ln -sf "/opt/${asset}/bin/nvim" /usr/local/bin/nvim
rm -f /tmp/nvim.tar.gz
nvim --version | head -n1

echo
echo "== running the installer =="
bash "${REPO}/scripts/setup.sh" --no-fonts | tee /tmp/setup.log

echo
echo "== assertions =="
assert_absent "$HOME/.local/share/nvim-dist" "no second Neovim was downloaded"
assert_absent "$HOME/.local/bin/nvim" "no managed nvim symlink was created"
assert_symlink_to "$HOME/.config/nvim" "${REPO}/nvim" "the config was still linked"
assert_contains /tmp/setup.log "used the existing" "the summary says the existing Neovim was reused"
assert_eq "$(command -v nvim)" "/usr/local/bin/nvim" "the pre-installed nvim is still the one on PATH"

# Plugins must have been installed with the pre-existing binary.
assert_exists "$HOME/.local/share/nvim/lazy/lazy.nvim" "plugins were installed with the existing Neovim"

finish
