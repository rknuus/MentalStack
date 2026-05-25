#!/bin/bash
# ccpm-commit-epic.sh — Coordinator: commit a single epic.md file.
#
# Usage:
#   bash ccpm-commit-epic.sh <initiative> <epic>
#   bash ccpm-commit-epic.sh <initiative> <epic> --summary "<line>"
#   bash ccpm-commit-epic.sh --json <initiative> <epic>
#
# Behavior:
#   - Runs mode detection (coord_init).
#   - When CCPM_TRACKED=false: emits a status note and exits 0 — epic file
#     stays in the working tree only when .ccpm/ is ignored.
#   - Otherwise: writes the canonical commit-message file and runs the FR-8
#     atomic commit recipe against the epic.md path.
#
# Subject convention:
#   - Default:           "Epic: <epic>"
#   - With --summary X:  "Epic: <epic> — X"  (e.g. "Epic: foo — 5 tasks")
#
# Architect-directory overlay (METHOD_TRACKED) is deferred to ACCPM via the
# agentify pipeline (Issue #127). TCCPM commits only the epic.md path.
#
# Exit status:
#   0   Commit created OR skipped (CCPM_TRACKED=false or empty diff).
#   1   Validation error.
#   2   Mode detection error.

set -eu

_self_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_self_dir/lib/coordinator-lib.sh"

_summary=""
_positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      export COORD_OUTPUT_MODE=json
      shift
      ;;
    --summary)
      _summary="${2:-}"
      shift 2
      ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 1
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do _positional+=("$1"); shift; done
      ;;
    *)
      _positional+=("$1")
      shift
      ;;
  esac
done

if [ "${#_positional[@]}" -lt 2 ]; then
  echo "ccpm-commit-epic: usage: bash ccpm-commit-epic.sh [--json] [--summary <line>] <initiative> <epic>" >&2
  exit 1
fi
_initiative="${_positional[0]}"
_epic="${_positional[1]}"

_epic_file=".ccpm/initiatives/$_initiative/$_epic/epic.md"
if [ ! -f "$_epic_file" ]; then
  echo "ccpm-commit-epic: epic file not found: $_epic_file" >&2
  exit 1
fi

if ! coord_init "$_initiative"; then
  exit $?
fi

if [ "${CCPM_TRACKED:-false}" != "true" ]; then
  coord_status "CCPM_TRACKED=false; epic file not committed (working tree only)"
  exit 0
fi

_msg="$(coord_msg_path epic "$_initiative" "$_epic")"
{
  if [ -n "$_summary" ]; then
    echo "Epic: $_epic — $_summary"
  else
    echo "Epic: $_epic"
  fi
} > "$_msg"

if ! coord_commit "$_msg" "$_epic_file"; then
  exit 1
fi
