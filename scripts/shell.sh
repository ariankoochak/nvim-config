#!/usr/bin/env bash
# Optional shell module (--with-shell): zsh + oh-my-zsh + powerlevel10k, and on
# macOS the iTerm2 shell integration that Automatic Profile Switching needs.
#
# Nothing in nvim/ depends on any of this; it is pure convenience.

OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"
OMZ_CUSTOM="${ZSH_CUSTOM:-${OMZ_DIR}/custom}"
P10K_DIR="${OMZ_CUSTOM}/themes/powerlevel10k"
ITERM2_INTEGRATION="$HOME/.iterm2_shell_integration.zsh"

install_shell() {
  log "Shell (zsh + oh-my-zsh + powerlevel10k)"

  _install_zsh
  # Order matters: the oh-my-zsh installer writes ~/.zshrc, so every edit of
  # ours has to happen after it ran.
  _install_omz
  _install_p10k
  _set_p10k_theme
  _install_iterm2_integration

  if [ "${SHELL:-}" != "$(command -v zsh 2>/dev/null)" ]; then
    manual "Make zsh your login shell:  chsh -s \"\$(command -v zsh)\""
    step "not running chsh automatically; see the summary"
  fi
}

_install_zsh() {
  if have zsh; then
    ok "zsh present ($(command -v zsh))"
    return 0
  fi
  if [ "$OS" = "macos" ]; then
    die "zsh is missing on macOS, which should be impossible. Aborting."
  fi
  step "apt-get install zsh"
  _apt_install "zsh"
  summary "Shell: installed zsh"
}

_install_omz() {
  if [ -d "$OMZ_DIR" ]; then
    ok "oh-my-zsh already at $OMZ_DIR"
    return 0
  fi
  step "installing oh-my-zsh"
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/omz.XXXXXX")"
  download "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "$tmp/install.sh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$tmp/install.sh" --unattended
  rm -rf "$tmp"
  summary "Shell: installed oh-my-zsh into $OMZ_DIR"
}

_install_p10k() {
  if [ -d "$P10K_DIR" ]; then
    ok "powerlevel10k already at $P10K_DIR"
    return 0
  fi
  step "cloning powerlevel10k"
  mkdir -p "$(dirname "$P10K_DIR")"
  git clone --depth 1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
  summary "Shell: cloned powerlevel10k into $P10K_DIR"
}

_set_p10k_theme() {
  local rc="$HOME/.zshrc"
  [ -f "$rc" ] || {
    manual "No ~/.zshrc found; set ZSH_THEME=\"powerlevel10k/powerlevel10k\" yourself."
    return 0
  }

  if grep -q '^ZSH_THEME="powerlevel10k/powerlevel10k"' "$rc"; then
    ok "ZSH_THEME already powerlevel10k"
    return 0
  fi

  if grep -q '^ZSH_THEME=' "$rc"; then
    # Only replace a *different* theme; sed -i.bak works on both GNU and BSD sed.
    sed_inplace 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$rc"
    ok "switched ZSH_THEME to powerlevel10k"
  else
    ensure_line "$rc" 'ZSH_THEME="powerlevel10k/powerlevel10k"'
  fi
  summary "Shell: ZSH_THEME set to powerlevel10k/powerlevel10k"
  manual "Run 'p10k configure' once to pick a powerlevel10k style."
}

_install_iterm2_integration() {
  [ "$OS" = "macos" ] || return 0
  [ -d "/Applications/iTerm.app" ] || return 0

  if [ ! -f "$ITERM2_INTEGRATION" ]; then
    step "downloading iTerm2 shell integration for zsh"
    download "https://iterm2.com/shell_integration/zsh" "$ITERM2_INTEGRATION"
    summary "Shell: installed iTerm2 shell integration ($ITERM2_INTEGRATION)"
  else
    ok "iTerm2 shell integration already installed"
  fi

  # powerlevel10k owns PS1, so the integration must not prepend its own
  # FTCS_PROMPT mark -- that is exactly what ITERM2_SQUELCH_MARK is for. The
  # host/path/job reporting that Automatic Profile Switching relies on still
  # happens.
  ensure_block "$HOME/.zshrc" "# >>> nvim-config iterm2 shell integration >>>" \
    'export ITERM2_SQUELCH_MARK=1  # powerlevel10k controls the prompt' \
    "[ -f \"${ITERM2_INTEGRATION}\" ] && source \"${ITERM2_INTEGRATION}\"" \
    "# <<< nvim-config iterm2 shell integration <<<"
}
