# shellcheck shell=sh
#
# PATH/environment shared by bash and zsh. Sourced from ~/.bashrc and ~/.zshrc
# by scripts/link.sh. Deliberately POSIX sh: no arrays, no [[ ]], no local.
#
# This file must stay independent of zsh, oh-my-zsh and powerlevel10k.

# ~/.local/bin holds the managed `nvim` symlink, the `fd` shim on Debian/Ubuntu
# and anything Mason exposes.
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) PATH="${HOME}/.local/bin:${PATH}" ;;
esac

# Homebrew's libpq (which provides psql) is keg-only, so it is never on PATH
# unless we put it there. Both the Apple Silicon and the Intel prefix are
# checked; only one of them exists on any given machine.
for _nvim_config_dir in /opt/homebrew/opt/libpq/bin /usr/local/opt/libpq/bin; do
  if [ -d "${_nvim_config_dir}" ]; then
    case ":${PATH}:" in
      *":${_nvim_config_dir}:"*) ;;
      *) PATH="${PATH}:${_nvim_config_dir}" ;;
    esac
  fi
done
unset _nvim_config_dir

export PATH
