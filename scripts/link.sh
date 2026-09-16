#!/usr/bin/env bash
# Symlink the Neovim config into place, and wire shell/env.sh into the rc files.

XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

NVIM_CONFIG_TARGET="${XDG_CONFIG}/nvim"

link_config() {
  log "Linking the Neovim configuration"

  local src first_install=1
  src="${DIR}/nvim"
  [ -d "$src" ] || die "Expected the config at $src but it is missing."

  if [ -L "$NVIM_CONFIG_TARGET" ] && [ "$(readlink "$NVIM_CONFIG_TARGET")" = "$src" ]; then
    first_install=0
  fi

  # Only on a first install: a previous Neovim setup leaves plugin data, state
  # and cache behind that would otherwise be mixed with LazyVim's.
  if [ "$first_install" -eq 1 ]; then
    backup_path "${XDG_DATA}/nvim"
    backup_path "${XDG_STATE}/nvim"
    backup_path "${XDG_CACHE}/nvim"
  fi

  link "$src" "$NVIM_CONFIG_TARGET"
  summary "Config: $NVIM_CONFIG_TARGET -> $src"
}

install_env() {
  log "Shell environment"

  local env_file marker line
  env_file="${DIR}/shell/env.sh"
  [ -f "$env_file" ] || die "Expected $env_file but it is missing."

  marker="# >>> nvim-config >>>"
  line="[ -f \"${env_file}\" ] && . \"${env_file}\"  ${marker}"

  local rc touched=""
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
      ensure_line "$rc" "$line"
      touched="${touched}$(basename "$rc") "
    fi
  done

  if [ -n "$touched" ]; then
    ok "sourced from: $touched"
    summary "Shell: ${env_file} sourced from ${touched}"
  else
    warn "Neither ~/.bashrc nor ~/.zshrc exists, so nothing was wired up.
         Add this line to your shell rc yourself:

             . \"${env_file}\""
    manual "Add '. \"${env_file}\"' to your shell rc file."
  fi

  # Make ~/.local/bin usable for the rest of *this* run too.
  case ":${PATH}:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
  esac
  export PATH
}
