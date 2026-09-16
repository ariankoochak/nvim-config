#!/usr/bin/env bash
# Neovim detection and installation.
#
# Policy (see README, "Neovim version policy"):
#   1. no nvim            -> install NVIM_INSTALL_VERSION into ~/.local/share/nvim-dist
#   2. nvim >= min        -> use it as-is, install nothing
#   3. nvim <  min        -> fail *before touching anything* with an upgrade hint
#   4. exception          -> an outdated nvim that *we* manage is upgraded in place
#
# preflight_neovim() only inspects the system. install_neovim() is the only
# function here that writes anything.

NVIM_DIST_DIR="${NVIM_DIST_DIR:-$HOME/.local/share/nvim-dist}"
NVIM_MANAGED_BIN="${NVIM_MANAGED_BIN:-$HOME/.local/bin/nvim}"

# Set by preflight_neovim():
#   NVIM          absolute path of the binary every later step must call
#   NVIM_ACTION   none | install | upgrade
#   NVIM_FOUND    path of the pre-existing nvim (empty when there is none)
#   NVIM_FOUND_VERSION
NVIM=""
NVIM_ACTION="none"
NVIM_FOUND=""
NVIM_FOUND_VERSION=""

# Scratch directory used while downloading; cleaned up by setup.sh's EXIT trap
# so an interrupted download never leaves anything behind.
NVIM_TMPDIR=""

# True when $1 is our own managed symlink pointing into $NVIM_DIST_DIR.
_nvim_is_managed() {
  local bin="$1" target
  [ "$bin" = "$NVIM_MANAGED_BIN" ] || return 1
  [ -L "$bin" ] || return 1
  target="$(readlink "$bin")"
  case "$target" in
    "$NVIM_DIST_DIR"/*) return 0 ;;
    *) return 1 ;;
  esac
}

_upgrade_hint() {
  local path="$1"
  case "$path" in
    */snap/*)
      printf '  This nvim comes from snap. Upgrade it with:\n\n      sudo snap refresh nvim\n'
      ;;
    /opt/homebrew/* | /usr/local/*)
      printf '  This nvim comes from Homebrew. Upgrade it with:\n\n      brew upgrade neovim\n'
      ;;
    /usr/bin/*)
      printf '%s' \
        '  This nvim comes from the Ubuntu archive, whose neovim package is too old
  for LazyVim and will never be new enough on an LTS release. Remove it and
  re-run this installer, which will then install a current Neovim into
  ~/.local (no sudo, no second copy on your PATH):

      sudo apt-get remove -y neovim neovim-runtime
'
      ;;
    *)
      printf '%s' '  Upgrade or remove this Neovim, then re-run the installer.
'
      ;;
  esac
}

preflight_neovim() {
  local found version mm
  found="$(command -v nvim 2>/dev/null || true)"

  if [ -z "$found" ]; then
    NVIM_ACTION="install"
    NVIM="$NVIM_MANAGED_BIN"
    step "no nvim found; will install $NVIM_INSTALL_VERSION into $NVIM_DIST_DIR"
    return 0
  fi

  NVIM_FOUND="$found"
  version="$(nvim_version_of "$found" || true)"
  if [ -z "$version" ]; then
    die "Found '$found' but could not parse its version from \`nvim --version\`.
  Nothing has been changed on your system."
  fi
  NVIM_FOUND_VERSION="$version"

  if version_ge "$version" "$NVIM_MIN_VERSION"; then
    NVIM_ACTION="none"
    NVIM="$found"
    mm="$(printf '%s' "$version" | cut -d. -f1-2)"
    if version_ge "$mm" "$NVIM_MAX_TESTED" && ! version_ge "$NVIM_MAX_TESTED" "$mm"; then
      warn "Neovim $version is newer than the most recent tested release ($NVIM_MAX_TESTED.x).
         Continuing anyway; open an issue if something misbehaves."
    fi
    step "using existing nvim $version ($found)"
    return 0
  fi

  if _nvim_is_managed "$found"; then
    NVIM_ACTION="upgrade"
    NVIM="$NVIM_MANAGED_BIN"
    step "managed nvim $version is outdated; will upgrade it to $NVIM_INSTALL_VERSION"
    return 0
  fi

  printf '%sERROR:%s Neovim is too old for this configuration.\n\n' "$C_RED" "$C_RESET" >&2
  {
    printf '  path:     %s\n' "$found"
    printf '  version:  %s\n' "$version"
    printf '  required: >= %s (LazyVim minimum)\n\n' "$NVIM_MIN_VERSION"
    _upgrade_hint "$found"
    printf '\n  Nothing has been changed on your system.\n'
  } >&2
  exit 1
}

install_neovim() {
  case "$NVIM_ACTION" in
    none)
      ok "Neovim $NVIM_FOUND_VERSION at $NVIM (unchanged)"
      summary "Neovim: used the existing $NVIM_FOUND_VERSION at ${NVIM_FOUND:-$NVIM} (nothing installed)"
      return 0
      ;;
    upgrade) log "Upgrading managed Neovim to $NVIM_INSTALL_VERSION" ;;
    install) log "Installing Neovim $NVIM_INSTALL_VERSION" ;;
  esac

  local url tmp tarball dest
  url="https://github.com/neovim/neovim/releases/download/${NVIM_INSTALL_VERSION}/${NVIM_ASSET}.tar.gz"
  dest="${NVIM_DIST_DIR}/${NVIM_ASSET}"

  NVIM_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/nvim-install.XXXXXX")"
  tmp="$NVIM_TMPDIR"

  tarball="${tmp}/${NVIM_ASSET}.tar.gz"
  step "downloading $url"
  download "$url" "$tarball"

  # Release tarballs downloaded by a browser carry a quarantine xattr on macOS.
  # curl does not set one, but clearing it is free insurance.
  if [ "$OS" = "macos" ] && have xattr; then
    xattr -c "$tarball" 2>/dev/null || true
  fi

  step "extracting"
  mkdir -p "$tmp/x"
  tar -xzf "$tarball" -C "$tmp/x"

  local extracted
  extracted="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [ -n "$extracted" ] || die "Unexpected archive layout in $url"
  [ -x "$extracted/bin/nvim" ] || die "No bin/nvim inside $url"

  mkdir -p "$NVIM_DIST_DIR" "$(dirname "$NVIM_MANAGED_BIN")"
  rm -rf "$dest"
  mv "$extracted" "$dest"

  # The managed symlink is ours: replace it without a backup dance.
  rm -f "$NVIM_MANAGED_BIN"
  ln -s "${dest}/bin/nvim" "$NVIM_MANAGED_BIN"

  NVIM="$NVIM_MANAGED_BIN"
  local installed
  installed="$(nvim_version_of "$NVIM" || true)"
  [ -n "$installed" ] || die "Installed Neovim at $NVIM does not run."

  rm -rf "$NVIM_TMPDIR"
  NVIM_TMPDIR=""

  ok "Neovim $installed installed at $NVIM"
  summary "Neovim: installed $installed into $dest, symlinked as $NVIM_MANAGED_BIN"
}
