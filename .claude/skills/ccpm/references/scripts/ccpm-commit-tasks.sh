#!/bin/bash
# ccpm-commit-tasks.sh — Coordinator: commit task files produced by epic
# decomposition.
#
# Usage:
#   bash ccpm-commit-tasks.sh <initiative> <epic>
#   bash ccpm-commit-tasks.sh --json <initiative> <epic>
#
# Behavior:
#   - Runs mode detection (coord_init).
#   - Skips when CCPM_TRACKED=false (task files stay in working tree only).
#   - Otherwise: counts task files (`[0-9]*.md` glob), writes the canonical
#     commit-message file with subject `Epic: <epic> — N tasks`, runs the
#     FR-8 atomic commit recipe with pathspec list:
#         .ccpm/initiatives/<i>/<e>/[0-9]*.md      (always)
#         .ccpm/next-id                            (when tracked)
#
# Architect-directory overlay (METHOD_TRACKED / ${METHOD_DIR}) and the
# four-corner ACCPM case are deferred to the agentify pipeline (Issue #127).
#
# Exit status:
#   0   Commit created OR skipped (CCPM_TRACKED=false or empty diff).
#   1   Validation error.
#   2   Mode detection error.

set -eu

_self_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_self_dir/lib/coordinator-lib.sh"

_positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      export COORD_OUTPUT_MODE=json
      shift
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
  echo "ccpm-commit-tasks: usage: bash ccpm-commit-tasks.sh [--json] <initiative> <epic>" >&2
  exit 1
fi
_initiative="${_positional[0]}"
_epic="${_positional[1]}"

_epic_dir=".ccpm/initiatives/$_initiative/$_epic"
if [ ! -d "$_epic_dir" ]; then
  echo "ccpm-commit-tasks: epic directory not found: $_epic_dir" >&2
  exit 1
fi

if ! coord_init "$_initiative"; then
  exit $?
fi

if [ "${CCPM_TRACKED:-false}" != "true" ]; then
  coord_status "CCPM_TRACKED=false; task files not committed (working tree only)"
  exit 0
fi

# Count task files for the subject. nullglob is needed so the glob expands
# to nothing (rather than the literal pattern) when no tasks exist.
shopt -s nullglob
_task_files=("$_epic_dir"/[0-9]*.md)
shopt -u nullglob
_task_count="${#_task_files[@]}"

# Build the pathspec list. The task-file glob is passed as a literal string
# so git's pathspec engine — not the shell — handles the match.
_pathspecs=("$_epic_dir/[0-9]*.md")

# .ccpm/next-id is appended only when the file exists AND is tracked
# (i.e. NOT matched by .gitignore).
if [ -f .ccpm/next-id ] && ! git check-ignore -q .ccpm/next-id 2>/dev/null; then
  _pathspecs+=(".ccpm/next-id")
fi

_msg="$(coord_msg_path tasks "$_initiative" "$_epic")"
echo "Epic: $_epic — $_task_count tasks" > "$_msg"

if ! coord_commit "$_msg" "${_pathspecs[@]}"; then
  exit 1
fi
