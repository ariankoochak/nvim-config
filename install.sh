#!/usr/bin/env bash
#
# Bootstrap for https://github.com/ariankoochak/nvim-config
#
#   curl -fsSL https://raw.githubusercontent.com/ariankoochak/nvim-config/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/ariankoochak/nvim-config/main/install.sh | bash -s -- --with-shell
#
# Everything lives inside main() so that a truncated download cannot execute a
# partial script: bash only runs the final line once the whole file is parsed.

set -euo pipefail

REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/ariankoochak/nvim-config.git}"
REPO_BRANCH="${NVIM_CONFIG_BRANCH:-main}"

main() {
  local dir
  dir="${NVIM_CONFIG_DIR:-$HOME/.nvim-config}"

  if ! command -v git >/dev/null 2>&1; then
    case "$(uname -s)" in
      Linux)
        echo "==> git is missing; installing it with apt-get" >&2
        if ! command -v sudo >/dev/null 2>&1; then
          echo "ERROR: neither git nor sudo is available. Install git and re-run." >&2
          exit 1
        fi
        sudo apt-get update -qq
        sudo apt-get install -y git
        ;;
      Darwin)
        cat >&2 <<'MSG'
ERROR: git is not installed.

On macOS git ships with the Command Line Developer Tools. Install them with:

    xcode-select --install

then re-run this installer. Nothing has been changed on your system.
MSG
        exit 1
        ;;
      *)
        echo "ERROR: unsupported platform '$(uname -s)'. Only Linux and macOS are supported." >&2
        exit 1
        ;;
    esac
  fi

  if [ -d "$dir/.git" ]; then
    echo "==> Updating existing checkout in $dir"
    git -C "$dir" fetch --quiet origin "$REPO_BRANCH"
    git -C "$dir" pull --ff-only --quiet origin "$REPO_BRANCH"
  elif [ -e "$dir" ]; then
    echo "ERROR: $dir exists but is not a git checkout. Move it away and re-run." >&2
    exit 1
  else
    echo "==> Cloning $REPO_URL into $dir"
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$dir"
  fi

  exec bash "$dir/scripts/setup.sh" "$@"
}

main "$@"
