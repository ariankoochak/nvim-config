#!/usr/bin/env bash
# Nerd Font installation (skipped with --no-fonts).

# Nerd Fonts v3 ships two names per face: the short fontconfig family
# ("JetBrainsMono NFM") and the typographic family that GUI pickers show
# ("JetBrainsMono Nerd Font Mono"). Both are matched when probing. The iTerm2
# profile refers to the same face by its PostScript name, JetBrainsMonoNFM-Regular.
FONT_FAMILY_NAME="${NERD_FONT} Nerd Font Mono"
FONT_FAMILY_SHORT="${NERD_FONT} NFM"
FONT_DIR_LINUX="$HOME/.local/share/fonts/${NERD_FONT}NerdFont"

_font_already_installed() {
  if have fc-list; then
    fc-list 2>/dev/null | grep -qE "${NERD_FONT} (NFM?|Nerd Font)" && return 0
  fi
  [ -d "$FONT_DIR_LINUX" ] && return 0
  return 1
}

install_fonts() {
  log "Nerd Font (${FONT_FAMILY_NAME})"

  if [ "$OS" = "macos" ]; then
    if brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
      ok "font-jetbrains-mono-nerd-font already installed"
    else
      step "brew install --cask font-jetbrains-mono-nerd-font"
      brew install --cask font-jetbrains-mono-nerd-font
      summary "Font: installed the ${FONT_FAMILY_NAME} cask"
    fi
  else
    if _font_already_installed; then
      ok "${FONT_FAMILY_NAME} already installed"
    else
      local url tmp
      url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/${NERD_FONT}.zip"
      tmp="$(mktemp -d "${TMPDIR:-/tmp}/nerd-font.XXXXXX")"
      step "downloading $url"
      download "$url" "$tmp/font.zip"
      mkdir -p "$FONT_DIR_LINUX"
      # Only the font files: an exclude list makes unzip print a "caution"
      # (and return 11) whenever one of the patterns matches nothing.
      unzip -qo "$tmp/font.zip" '*.ttf' -d "$FONT_DIR_LINUX"
      rm -rf "$tmp"
      step "running fc-cache -f"
      fc-cache -f >/dev/null 2>&1 || warn "fc-cache failed; the font may not be picked up until you log out"
      ok "installed into $FONT_DIR_LINUX"
      summary "Font: installed ${FONT_FAMILY_NAME} ${NERD_FONT_VERSION} into $FONT_DIR_LINUX"
    fi
  fi

  # The installer can put font files on disk, but no terminal emulator picks a
  # font on its own. iTerm2 is the one exception (scripts/terminal.sh sets it
  # inside our Dynamic Profile).
  if [ "$OS" = "macos" ]; then
    manual "Terminal.app: set the font to '${FONT_FAMILY_NAME}' in Settings > Profiles > Text."
  else
    manual "Select '${FONT_FAMILY_NAME}' (listed as '${FONT_FAMILY_SHORT}' by some pickers) as your terminal font -- GNOME Terminal: Preferences > Profile > Text > Custom font."
  fi
}
