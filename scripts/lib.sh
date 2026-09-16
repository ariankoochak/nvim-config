#!/usr/bin/env bash
# Shared helpers for every installer module.
#
# Sourced (never executed) by scripts/setup.sh. Written for bash 3.2 so it runs
# on a stock macOS /bin/bash as well as on GNU bash under Ubuntu.

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_BLUE=$'\033[34m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_DIM=$'\033[2m'
else
  C_RESET=""
  C_BLUE=""
  C_YELLOW=""
  C_RED=""
  C_GREEN=""
  C_DIM=""
fi

log() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
step() { printf '%s  ->%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
ok() { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%sWARNING:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() {
  printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Summary / backup bookkeeping
#
# Collected as newline separated strings (bash 3.2 has no associative arrays and
# `local -a` behaves differently between versions, so plain strings it is).
# ---------------------------------------------------------------------------

SUMMARY=""
MANUAL_STEPS=""
BACKUPS=""

summary() { SUMMARY="${SUMMARY}${1}"$'\n'; }
manual() { MANUAL_STEPS="${MANUAL_STEPS}${1}"$'\n'; }

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

# Sets: OS (linux|macos), ARCH (x86_64|arm64), NVIM_ASSET (release asset name)
detect_os() {
  local uname_s uname_m
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"

  case "$uname_s" in
    Linux) OS="linux" ;;
    Darwin) OS="macos" ;;
    *) die "Unsupported operating system '$uname_s'. Only Linux and macOS are supported." ;;
  esac

  case "$uname_m" in
    x86_64 | amd64) ARCH="x86_64" ;;
    arm64 | aarch64) ARCH="arm64" ;;
    *) die "Unsupported architecture '$uname_m'. Only x86_64 and arm64 are supported." ;;
  esac

  case "${OS}-${ARCH}" in
    linux-x86_64) NVIM_ASSET="nvim-linux-x86_64" ;;
    linux-arm64) NVIM_ASSET="nvim-linux-arm64" ;;
    macos-arm64) NVIM_ASSET="nvim-macos-arm64" ;;
    macos-x86_64) NVIM_ASSET="nvim-macos-x86_64" ;;
  esac

  export OS ARCH NVIM_ASSET
}

# Darwin kernel major version (25 == macOS 26). Prints 0 on non-macOS.
darwin_major() {
  if [ "${OS:-}" = "macos" ]; then
    uname -r | cut -d. -f1
  else
    printf '0'
  fi
}

# ---------------------------------------------------------------------------
# Version comparison
#
# Pure bash: `sort -V` is unavailable on older macOS and `sort -t. -k1,1n ...`
# is fiddly. Compares up to three dotted numeric components and ignores any
# pre-release suffix ("0.12.0-dev" is treated as "0.12.0").
# ---------------------------------------------------------------------------

# version_ge A B -> exit 0 when A >= B
# No subshells and no external tools: parameter expansion only.
version_ge() {
  local a="${1%%-*}" b="${2%%-*}" i=0 av bv
  a="${a#v}"
  b="${b#v}"
  while [ "$i" -lt 3 ]; do
    av="${a%%.*}"
    if [ "$a" = "$av" ]; then a=""; else a="${a#*.}"; fi
    bv="${b%%.*}"
    if [ "$b" = "$bv" ]; then b=""; else b="${b#*.}"; fi

    av="${av//[!0-9]/}"
    bv="${bv//[!0-9]/}"
    av="${av:-0}"
    bv="${bv:-0}"

    if [ "$((10#$av))" -gt "$((10#$bv))" ]; then return 0; fi
    if [ "$((10#$av))" -lt "$((10#$bv))" ]; then return 1; fi
    i=$((i + 1))
  done
  return 0
}

# Extracts "0.12.0" from any of:
#   NVIM v0.11.2
#   NVIM v0.12.0-dev-123+g1a2b3c4
#   NVIM v0.12.5
nvim_version_of() {
  local bin="$1" first
  first="$("$bin" --version 2>/dev/null | head -n 1)" || return 1
  # shellcheck disable=SC2001  # the sed form is clearer than bash substitution here
  printf '%s' "$first" | sed -n 's/^NVIM v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p'
}

# ---------------------------------------------------------------------------
# Filesystem helpers
# ---------------------------------------------------------------------------

TIMESTAMP="$(date +%Y%m%d%H%M%S)"

# backup PATH -> move an existing path out of the way, recording it.
backup_path() {
  local p="$1" b
  if [ -e "$p" ] || [ -L "$p" ]; then
    b="${p}.bak.${TIMESTAMP}"
    mv "$p" "$b"
    BACKUPS="${BACKUPS}${b}"$'\n'
    step "backed up $p -> $b"
  fi
}

# link SRC DST -> symlink DST to SRC, backing up whatever was there before.
# Idempotent: an existing correct symlink is left alone.
link() {
  local src="$1" dst="$2" cur
  if [ -L "$dst" ]; then
    cur="$(readlink "$dst")"
    if [ "$cur" = "$src" ]; then
      ok "$dst already links to $src"
      return 0
    fi
  fi
  backup_path "$dst"
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  ok "linked $dst -> $src"
}

# ensure_line FILE LINE -> append LINE to FILE unless an identical line exists.
# Does nothing when FILE does not exist (the caller decides about creating it).
ensure_line() {
  local file="$1" line="$2"
  [ -f "$file" ] || return 0
  if grep -qxF -- "$line" "$file" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$line" >>"$file"
  step "added to $(basename "$file"): $line"
}

# ensure_block FILE MARKER LINE... -> append a marked block once.
ensure_block() {
  local file="$1" marker="$2"
  shift 2
  [ -f "$file" ] || return 0
  if grep -qF -- "$marker" "$file" 2>/dev/null; then
    return 0
  fi
  {
    printf '\n%s\n' "$marker"
    printf '%s\n' "$@"
  } >>"$file"
  step "added block to $(basename "$file") ($marker)"
}

# Portable in-place sed (GNU sed needs an argument for -i, BSD sed needs it too
# but interprets an empty one differently -- using a suffix works on both).
sed_inplace() {
  local expr="$1" file="$2"
  sed -i.bak "$expr" "$file"
  rm -f "${file}.bak"
}

# Download URL to FILE, preferring curl and falling back to wget.
download() {
  local url="$1" out="$2"
  if have curl; then
    curl -fsSL --retry 3 -o "$out" "$url"
  elif have wget; then
    wget -qO "$out" "$url"
  else
    die "Neither curl nor wget is available; cannot download $url"
  fi
}
