#!/usr/bin/env bash
#
# Installer scenario runner. Every scenario gets its own throwaway container, so
# nothing here can touch the machine you run it on.
#
#   test/install/run.sh                # all scenarios
#   test/install/run.sh 02 04          # just those
#
# Requires Docker.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
IMAGE="nvim-config-installer-test"

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: docker is required for the installer tests." >&2
  exit 1
}

# Newline separated rather than an array: bash 3.2 (macOS) trips over an empty
# array under `set -u`.
scenarios=""
if [ $# -gt 0 ]; then
  for want in "$@"; do
    for file in "${HERE}"/scenarios/"${want}"*.sh; do
      [ -f "$file" ] && scenarios="${scenarios}${file}"$'\n'
    done
  done
else
  for file in "${HERE}"/scenarios/*.sh; do
    [ -f "$file" ] && scenarios="${scenarios}${file}"$'\n'
  done
fi

if [ -z "$scenarios" ]; then
  echo "ERROR: no scenarios matched." >&2
  exit 1
fi

echo "==> building $IMAGE"
docker build -q -t "$IMAGE" -f "${HERE}/Dockerfile" "$ROOT" >/dev/null

status=0
while IFS= read -r scenario; do
  [ -n "$scenario" ] || continue
  name="$(basename "$scenario" .sh)"
  printf '\n\033[34m==> scenario %s\033[0m\n' "$name"
  if docker run --rm "$IMAGE" bash "/home/tester/nvim-config/test/install/scenarios/$(basename "$scenario")"; then
    printf '\033[32m==> %s OK\033[0m\n' "$name"
  else
    printf '\033[31m==> %s FAILED\033[0m\n' "$name"
    status=1
  fi
done <<EOF
${scenarios}
EOF

exit "$status"
