#!/bin/bash
# ccpm-push-branch.sh — Coordinator: push the initiative branch to origin.
#
# Usage:
#   bash ccpm-push-branch.sh <initiative>
#   bash ccpm-push-branch.sh --json <initiative>
#
# Behavior:
#   - Runs mode detection.
#   - When ONLINE=true: `git push origin initiative/<init>`.
#   - When ONLINE=false: silent skip with a status note ("skipped: offline").
#   - Never uses --force. Pull-rebase + retry on a non-fast-forward reject
#     is the caller's responsibility.
#
# Exit status:
#   0   Pushed OR skipped (ONLINE=false).
#   1   Validation error or push failure.
#   2   Mode detection error.

set -eu

_self_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_self_dir/lib/coordinator-lib.sh"

case "${1:-}" in
  --json)
    export COORD_OUTPUT_MODE=json
    shift
    ;;
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
    ;;
esac
_initiative="${1:-}"
if [ -z "$_initiative" ]; then
  echo "ccpm-push-branch: usage: bash ccpm-push-branch.sh [--json] <initiative>" >&2
  exit 1
fi

if ! coord_init "$_initiative"; then
  exit $?
fi

if [ "${ONLINE:-false}" != "true" ]; then
  coord_status "skipped: offline"
  exit 0
fi

if coord_push_branch "initiative/$_initiative"; then
  coord_status "pushed: initiative/$_initiative"
else
  rc=$?
  coord_status "push-failed: initiative/$_initiative"
  exit "$rc"
fi
