#!/bin/bash
# ccpm-commit-initiative.sh — Coordinator: commit the initiative file.
#
# Usage:
#   bash ccpm-commit-initiative.sh <initiative>
#   bash ccpm-commit-initiative.sh --json <initiative>
#
# Behavior:
#   - Runs mode detection (coord_init).
#   - When CCPM_TRACKED=false: emits a status note and exits 0 — initiative
#     files live in the working tree only when .ccpm/ is ignored. No commit.
#   - Otherwise: writes the canonical commit-message file, runs the FR-8
#     atomic commit recipe (`git commit -F <msg> -- <pathspec>` + rm), and
#     emits a status note.
#
# Exit status:
#   0   Commit created OR skipped (CCPM_TRACKED=false or empty diff).
#   1   Validation error (missing initiative, missing initiative file).
#   2   Mode detection error (e.g. METHOD_DIR multi-match).
#
# IMPORTANT: Caller must cd to the git project root before invoking.

set -eu

_self_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_self_dir/lib/coordinator-lib.sh"

# Parse args: optional leading --json, then <initiative>.
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
  echo "ccpm-commit-initiative: usage: bash ccpm-commit-initiative.sh [--json] <initiative>" >&2
  exit 1
fi

_initiative_file=".ccpm/initiatives/$_initiative/$_initiative.md"
if [ ! -f "$_initiative_file" ]; then
  echo "ccpm-commit-initiative: initiative file not found: $_initiative_file" >&2
  exit 1
fi

if ! coord_init "$_initiative"; then
  exit $?
fi

if [ "${CCPM_TRACKED:-false}" != "true" ]; then
  coord_status "CCPM_TRACKED=false; initiative file not committed (working tree only)"
  exit 0
fi

# Extract one-line description from the initiative's frontmatter.
_description="$(grep -E '^description:[[:space:]]*' "$_initiative_file" \
  | head -n 1 \
  | sed 's/^description:[[:space:]]*//')"

_msg="$(coord_msg_path initiative "$_initiative")"
{
  echo "Initiative: $_initiative"
  if [ -n "$_description" ]; then
    echo
    echo "$_description"
  fi
} > "$_msg"

if ! coord_commit "$_msg" "$_initiative_file"; then
  exit 1
fi
