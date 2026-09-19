#!/usr/bin/env bash
# macOS terminal integration (skipped with --no-terminal, and a no-op on Linux).
#
# Cmd keys never reach a program running in a terminal: the terminal emulator
# eats them. Rather than keeping a macOS-specific Neovim config, the translation
# happens at the terminal layer, so nvim/ stays identical on every platform.

ITERM_APP="/Applications/iTerm.app"
ITERM_DYNAMIC_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
ITERM_PROFILE_SRC=""
TERMINAL_PROFILE_SRC=""

install_terminal() {
  [ "$OS" = "macos" ] || return 0

  log "macOS terminal integration"

  ITERM_PROFILE_SRC="${DIR}/terminal/macos/nvim-config.json"
  TERMINAL_PROFILE_SRC="${DIR}/terminal/macos/nvim-config.terminal"

  _install_iterm2_profile
  _install_terminal_app_profile
  _maybe_disable_space_shortcuts
}

_install_iterm2_profile() {
  if [ ! -d "$ITERM_APP" ]; then
    step "iTerm2 is not installed; skipping its Dynamic Profile"
    return 0
  fi

  [ -f "$ITERM_PROFILE_SRC" ] || die "Missing $ITERM_PROFILE_SRC"

  mkdir -p "$ITERM_DYNAMIC_DIR"
  link "$ITERM_PROFILE_SRC" "${ITERM_DYNAMIC_DIR}/nvim-config.json"
  summary "iTerm2: Dynamic Profile 'nvim-config' installed (Cmd+S/C/V, Ctrl+Backspace, Cmd+(Shift+)Arrow, left Option as Esc+)"

  # Automatic Profile Switching only works with Shell Integration installed.
  if [ -f "$HOME/.iterm2_shell_integration.zsh" ] || [ -f "$HOME/.iterm2_shell_integration.bash" ]; then
    ok "iTerm2 Shell Integration present (needed by Automatic Profile Switching)"
  else
    warn "iTerm2 Shell Integration is not installed.

         Without it, Automatic Profile Switching cannot activate the
         'nvim-config' profile while nvim runs, so the Cmd bindings stay off.
         Install it with --with-shell, or manually:

             curl -L https://iterm2.com/shell_integration/install_shell_integration.sh | bash"
    manual "Install iTerm2 Shell Integration so Automatic Profile Switching can activate the nvim-config profile."
  fi

  manual "iTerm2: restart iTerm2 once so it picks up the Dynamic Profile."
  manual "iTerm2: inside ssh the foreground job is 'ssh', not 'nvim', so the profile does not switch -- use Ctrl there."
}

_install_terminal_app_profile() {
  [ -f "$TERMINAL_PROFILE_SRC" ] || die "Missing $TERMINAL_PROFILE_SRC"

  if [ -n "${CI:-}" ] || [ -n "${NVIM_CONFIG_NO_OPEN:-}" ]; then
    step "not importing the Terminal.app profile automatically (CI)"
  else
    step "importing the Terminal.app profile (opens Terminal.app in the background)"
    open -g "$TERMINAL_PROFILE_SRC" 2>/dev/null ||
      warn "Could not import $TERMINAL_PROFILE_SRC automatically; open it by hand."
  fi

  summary "Terminal.app: profile 'nvim-config' provided (Use Option as Meta key enabled)"
  manual "Terminal.app: Settings > Profiles > nvim-config > Text > Font -> 'JetBrainsMono Nerd Font Mono'."
  manual "Terminal.app: click 'Default' on the nvim-config profile if you want it for new windows."
  manual "Terminal.app: Cmd keys cannot be remapped there -- use Ctrl+S / Ctrl+C / Ctrl+V and Ctrl+Arrow."
}

# macOS binds Ctrl+Left / Ctrl+Right to "Move left/right a space" in Mission
# Control, which swallows <C-Left>/<C-Right> before any terminal sees them.
# Symbolic hotkey ids: 79/80 = move left a space, 81/82 = move right a space.
_maybe_disable_space_shortcuts() {
  if [ "$MACOS_DISABLE_SPACE_SHORTCUTS" -ne 1 ]; then
    manual "macOS binds Ctrl+Left/Right to Mission Control spaces. Re-run with --macos-disable-space-shortcuts to turn them off, or clear them in System Settings > Keyboard > Keyboard Shortcuts > Mission Control."
    return 0
  fi

  log "Disabling the Mission Control space shortcuts"

  local backup="$HOME/com.apple.symbolichotkeys.plist.bak.${TIMESTAMP}"
  if defaults export com.apple.symbolichotkeys "$backup" 2>/dev/null; then
    BACKUPS="${BACKUPS}${backup}"$'\n'
    step "backed up the symbolic hotkeys to $backup"
  fi

  local id
  for id in 79 80 81 82; do
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$id" \
      '<dict><key>enabled</key><false/></dict>'
  done

  local activate="/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
  [ -x "$activate" ] && "$activate" -u 2>/dev/null || true

  ok "Ctrl+Left / Ctrl+Right freed up (hotkeys 79-82 disabled)"
  summary "macOS: disabled Mission Control space shortcuts (symbolic hotkeys 79, 80, 81, 82)"
  manual "Log out and back in for the Mission Control shortcut change to take effect."
}
