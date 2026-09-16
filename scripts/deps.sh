#!/usr/bin/env bash
# System dependencies.
#
# preflight_deps() only inspects. install_deps() installs what is missing and is
# a no-op when everything is already there.

# "package:command" pairs. The command is what we probe for, so re-runs skip
# work instead of shelling out to the package manager every time.
APT_PACKAGES="
git:git
curl:curl
unzip:unzip
tar:tar
build-essential:cc
ripgrep:rg
fd-find:fdfind
postgresql-client:psql
xclip:xclip
wl-clipboard:wl-copy
fontconfig:fc-cache
"

BREW_PACKAGES="
ripgrep:rg
fd:fd
"

# Set by preflight_deps()
DEPS_MISSING=""
NODE_OK=0
NODE_VERSION=""

_missing_apt_packages() {
  local entry pkg cmd out=""
  for entry in $APT_PACKAGES; do
    pkg="${entry%%:*}"
    cmd="${entry##*:}"
    have "$cmd" || out="${out}${pkg} "
  done
  printf '%s' "$out"
}

_missing_brew_packages() {
  local entry pkg cmd out=""
  for entry in $BREW_PACKAGES; do
    pkg="${entry%%:*}"
    cmd="${entry##*:}"
    have "$cmd" || out="${out}${pkg} "
  done
  # libpq is keg-only: `psql` is never on PATH just because the formula is
  # installed, so probe the cellar instead of the command.
  if ! brew --prefix libpq >/dev/null 2>&1; then
    out="${out}libpq "
  fi
  printf '%s' "$out"
}

preflight_deps() {
  if [ "$OS" = "macos" ]; then
    if ! have brew; then
      die "Homebrew is required on macOS but was not found.

  Install it with:

      /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"

  then re-run this installer. Nothing has been changed on your system."
    fi
    DEPS_MISSING="$(_missing_brew_packages)"
  else
    if ! have apt-get; then
      die "This installer supports Debian/Ubuntu (apt-get) on Linux, which was not found.

  Install these yourself and re-run: git curl unzip tar build-essential ripgrep
  fd-find postgresql-client xclip wl-clipboard fontconfig.
  Nothing has been changed on your system."
    fi
    DEPS_MISSING="$(_missing_apt_packages)"
    if [ -n "$DEPS_MISSING" ] && [ "$(id -u)" -ne 0 ] && ! have sudo; then
      die "Missing packages ($DEPS_MISSING) but neither root nor sudo is available.
  Nothing has been changed on your system."
    fi
  fi

  # Node is never installed here; it is only reported on.
  if have node && have npm; then
    NODE_VERSION="$(node --version 2>/dev/null | sed 's/^v//')"
    if version_ge "$NODE_VERSION" "${NODE_MIN_MAJOR}.0.0"; then
      NODE_OK=1
    fi
  fi
}

_apt_install() {
  if [ "$(id -u)" -eq 0 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    # shellcheck disable=SC2086  # deliberate word splitting of the package list
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $1
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    # shellcheck disable=SC2086
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $1
  fi
}

install_deps() {
  log "System dependencies"

  if [ -z "$DEPS_MISSING" ]; then
    ok "all system dependencies already present"
  elif [ "$OS" = "macos" ]; then
    step "brew install $DEPS_MISSING"
    # shellcheck disable=SC2086
    brew install $DEPS_MISSING
    summary "Dependencies: brew installed $DEPS_MISSING"
  else
    step "apt-get install $DEPS_MISSING"
    _apt_install "$DEPS_MISSING"
    summary "Dependencies: apt installed $DEPS_MISSING"
  fi

  # Debian/Ubuntu ship fd as `fdfind`; LazyVim and this config expect `fd`.
  if [ "$OS" = "linux" ] && have fdfind && ! have fd; then
    mkdir -p "$HOME/.local/bin"
    if [ ! -e "$HOME/.local/bin/fd" ]; then
      ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
      ok "linked ~/.local/bin/fd -> $(command -v fdfind)"
    fi
  fi

  _report_node
  _report_treesitter_cli
}

_report_node() {
  if [ "$NODE_OK" -eq 1 ]; then
    ok "Node $NODE_VERSION (>= $NODE_MIN_MAJOR)"
    return 0
  fi
  if [ -z "$NODE_VERSION" ]; then
    warn "node/npm not found on PATH.

         This repo never installs Node -- you manage it with your version
         manager. Without it the following will NOT be installed:
           - TypeScript/JavaScript LSP (vtsls), eslint, prettier
           - the tree-sitter CLI that nvim-treesitter's main branch wants
         Install Node >= $NODE_MIN_MAJOR and re-run: bash ~/.nvim-config/scripts/setup.sh"
    manual "Install Node >= $NODE_MIN_MAJOR, then re-run the installer to get the TS/ESLint/Prettier tooling."
  else
    warn "Node $NODE_VERSION is older than the required $NODE_MIN_MAJOR.
         TS/ESLint/Prettier tooling will not install. Upgrade Node and re-run."
    manual "Upgrade Node to >= $NODE_MIN_MAJOR, then re-run the installer."
  fi
}

_report_treesitter_cli() {
  # LazyVim pins nvim-treesitter to its `main` branch, which needs the
  # tree-sitter CLI. LazyVim installs it itself through Mason
  # (`tree-sitter-cli`, an npm package) -- see lazyvim/util/treesitter.lua's
  # ensure_treesitter_cli(). There is no tree-sitter CLI in the Ubuntu archive
  # or in a Homebrew formula we want to pin, so we only report on it.
  if have tree-sitter; then
    ok "tree-sitter CLI found on PATH"
  elif [ "$NODE_OK" -eq 1 ]; then
    step "tree-sitter CLI missing; LazyVim will install it via Mason (tree-sitter-cli)"
  else
    warn "tree-sitter CLI missing and Node is unavailable, so Mason cannot install it.
         Treesitter parsers that must be generated from a grammar will fail."
  fi
}
