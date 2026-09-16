#!/usr/bin/env bash
#
# Orchestrator. Normally reached through install.sh, but safe to run directly:
#
#     bash ~/.nvim-config/scripts/setup.sh [flags]
#
# Guiding rule: every check that can fail runs in the preflight phase, before
# anything on the machine is touched. If this script exits non-zero during
# preflight, nothing was modified.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib.sh
. "${DIR}/scripts/lib.sh"
# shellcheck source=versions.env
. "${DIR}/versions.env"
# shellcheck source=scripts/neovim.sh
. "${DIR}/scripts/neovim.sh"
# shellcheck source=scripts/deps.sh
. "${DIR}/scripts/deps.sh"
# shellcheck source=scripts/fonts.sh
. "${DIR}/scripts/fonts.sh"
# shellcheck source=scripts/link.sh
. "${DIR}/scripts/link.sh"
# shellcheck source=scripts/shell.sh
. "${DIR}/scripts/shell.sh"
# shellcheck source=scripts/terminal.sh
. "${DIR}/scripts/terminal.sh"
# shellcheck source=scripts/post.sh
. "${DIR}/scripts/post.sh"

WITH_SHELL=0
DO_FONTS=1
DO_TERMINAL=1
MACOS_DISABLE_SPACE_SHORTCUTS=0

usage() {
  cat <<'USAGE'
nvim-config setup

Usage:
  bash scripts/setup.sh [flags]
  curl -fsSL https://raw.githubusercontent.com/ariankoochak/nvim-config/main/install.sh | bash -s -- [flags]

Flags:
  --with-shell                      Also install zsh, oh-my-zsh and powerlevel10k
                                    (and, on macOS with iTerm2, its Shell Integration).
  --no-fonts                        Do not install the Nerd Font.
  --no-terminal                     Do not install the macOS terminal integration.
  --macos-disable-space-shortcuts   Disable the macOS Mission Control shortcuts that
                                    swallow Ctrl+Left / Ctrl+Right. Opt-in; needs a
                                    logout to take effect.
  -h, --help                        Show this help.

Environment:
  NVIM_CONFIG_DIR   Where the repo lives (default ~/.nvim-config).
USAGE
}

parse_flags() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --with-shell) WITH_SHELL=1 ;;
      --no-fonts) DO_FONTS=0 ;;
      --no-terminal) DO_TERMINAL=0 ;;
      --macos-disable-space-shortcuts) MACOS_DISABLE_SPACE_SHORTCUTS=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown flag: $1"
        ;;
    esac
    shift
  done
}

cleanup() {
  [ -n "${NVIM_TMPDIR:-}" ] && rm -rf "$NVIM_TMPDIR"
  return 0
}

print_summary() {
  printf '\n%s%s%s\n' "$C_GREEN" "=== Done ===" "$C_RESET"

  printf '\n%sWhat changed%s\n' "$C_BLUE" "$C_RESET"
  if [ -n "$SUMMARY" ]; then
    printf '%s' "$SUMMARY" | sed '/^$/d; s/^/  - /'
  else
    printf '  - nothing\n'
  fi

  if [ -n "$BACKUPS" ]; then
    printf '\n%sBackups%s\n' "$C_BLUE" "$C_RESET"
    printf '%s' "$BACKUPS" | sed '/^$/d; s/^/  - /'
  fi

  if [ -n "$MANUAL_STEPS" ]; then
    printf '\n%sStill up to you%s\n' "$C_YELLOW" "$C_RESET"
    printf '%s' "$MANUAL_STEPS" | sed '/^$/d; s/^/  - /'
  fi

  local on_path
  on_path="$(command -v nvim 2>/dev/null || true)"
  if [ "$on_path" != "$NVIM" ]; then
    printf '\n%sOpen a new terminal%s\n' "$C_YELLOW" "$C_RESET"
    if [ -z "$on_path" ]; then
      printf '  No nvim is on the PATH of this shell yet. The one that was set up is\n'
    else
      printf '  nvim currently resolves to %s in this shell, but the one that was set up is\n' "$on_path"
    fi
    printf '  %s -- start a new shell (or source ~/.bashrc / ~/.zshrc) to pick it up.\n' "$NVIM"
  fi

  printf '\n  Start Neovim with: %s\n\n' "$NVIM"
}

main() {
  parse_flags "$@"
  trap cleanup EXIT

  detect_os
  log "Platform: ${OS}/${ARCH}"

  # ---- preflight: look, never touch -------------------------------------
  log "Preflight"
  preflight_deps
  preflight_neovim
  ok "preflight passed; starting installation"

  # ---- changes begin here ------------------------------------------------
  install_deps
  install_neovim

  if [ "$DO_FONTS" -eq 1 ]; then
    install_fonts
  else
    step "--no-fonts: skipping font installation"
  fi

  link_config
  install_env

  if [ "$WITH_SHELL" -eq 1 ]; then
    install_shell
  else
    step "no --with-shell: leaving zsh/oh-my-zsh/powerlevel10k alone"
  fi

  if [ "$DO_TERMINAL" -eq 1 ]; then
    install_terminal
  else
    step "--no-terminal: skipping the macOS terminal integration"
  fi

  run_post
  print_summary
}

main "$@"
