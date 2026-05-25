#!/bin/bash
# ccpm-commit-task-work.sh — Coordinator: per-agent task-work commit.
#
# Usage:
#   bash ccpm-commit-task-work.sh <initiative> <epic> <task-id> \
#        --message-file <path> [--push] [--json] -- <code-path…>
#
# The agent pre-writes a commit-message file with subject
# `Issue #<task-id>: <description>` and any body/trailers. The coordinator
# validates the subject format, assembles the pathspec list (code paths +
# optional progress files), runs the FR-8 atomic commit recipe, and
# optionally pushes the initiative branch when --push is given (gated on
# ONLINE).
#
# Behavior:
#   - When CCPM_TRACKED=true: appends `.ccpm/initiatives/<i>/<e>/updates/<task-id>/*.md`
#     to the pathspec list (the agent's progress file).
#   - On commit success: the agent's --message-file is removed.
#   - On commit failure: the agent's --message-file is preserved for
#     diagnosis (the agent can inspect, fix, and retry).
#
# Architect-directory overlay (METHOD_TRACKED / ${METHOD_DIR}) is deferred
# to the agentify pipeline (Issue #127).
#
# Concurrency: parallel agents on distinct task IDs use distinct message
# files (path includes <task-id>), so no message-file collision. Branch
# ref locking serializes their `git commit` invocations.
#
# Exit status:
#   0   Commit created OR empty diff (no-op).
#   1   Validation error (missing args, bad subject, missing message file,
#       commit failure).
#   2   Mode detection error.

set -eu

_self_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_self_dir/lib/coordinator-lib.sh"

_message_file=""
_push=0
_positional=()
_code_paths=()
_seen_dashdash=0

while [ $# -gt 0 ]; do
  if [ "$_seen_dashdash" -eq 1 ]; then
    _code_paths+=("$1"); shift; continue
  fi
  case "$1" in
    --json)
      export COORD_OUTPUT_MODE=json
      shift
      ;;
    --message-file)
      _message_file="${2:-}"
      shift 2
      ;;
    --push)
      _push=1
      shift
      ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 1
      ;;
    --)
      _seen_dashdash=1
      shift
      ;;
    *)
      _positional+=("$1")
      shift
      ;;
  esac
done

if [ "${#_positional[@]}" -lt 3 ]; then
  echo "ccpm-commit-task-work: usage: bash ccpm-commit-task-work.sh <initiative> <epic> <task-id> --message-file <path> [--push] [--json] -- <code-path...>" >&2
  exit 1
fi
_initiative="${_positional[0]}"
_epic="${_positional[1]}"
_task_id="${_positional[2]}"

if [ -z "$_message_file" ]; then
  echo "ccpm-commit-task-work: --message-file is required" >&2
  exit 1
fi
if [ ! -f "$_message_file" ]; then
  echo "ccpm-commit-task-work: message file not found: $_message_file" >&2
  exit 1
fi

if [ "${#_code_paths[@]}" -eq 0 ]; then
  echo "ccpm-commit-task-work: at least one code-path required after --" >&2
  exit 1
fi

# Validate the subject line: first non-empty line must match
# "Issue #<task-id>: ...".
_subject="$(grep -m 1 -v '^[[:space:]]*$' "$_message_file" 2>/dev/null || true)"
if ! echo "$_subject" | grep -qE "^Issue #${_task_id}: "; then
  echo "ccpm-commit-task-work: message subject must start with 'Issue #${_task_id}: ' (got: '$_subject')" >&2
  exit 1
fi

if ! coord_init "$_initiative"; then
  exit $?
fi

_pathspecs=()
for p in "${_code_paths[@]}"; do _pathspecs+=("$p"); done

# Append the progress-file glob ONLY when (a) CCPM_TRACKED=true, AND (b) the
# updates dir exists with at least one .md file. `git commit -- <pathspec>`
# requires every pathspec to match at least one file; a zero-match glob would
# fail the entire commit.
if [ "${CCPM_TRACKED:-false}" = "true" ]; then
  _updates_dir=".ccpm/initiatives/$_initiative/$_epic/updates/$_task_id"
  if [ -d "$_updates_dir" ]; then
    shopt -s nullglob
    _updates_files=("$_updates_dir"/*.md)
    shopt -u nullglob
    if [ "${#_updates_files[@]}" -gt 0 ]; then
      _pathspecs+=("$_updates_dir/*.md")
    fi
  fi
fi

# Backup the message file so we can restore it on commit failure.
# coord_commit unconditionally removes its <msg-file> argument; passing the
# agent's file directly would lose it on a real error. Workaround: hand
# coord_commit a temp copy and clean up the original ourselves.
_msg_tmp="$(mktemp -t ccpm-commit-task-work.XXXXXX)"
cp "$_message_file" "$_msg_tmp"

if coord_commit "$_msg_tmp" "${_pathspecs[@]}"; then
  rm -f "$_message_file"
else
  rm -f "$_msg_tmp"
  exit 1
fi

if [ "$_push" -eq 1 ]; then
  coord_push_branch "initiative/$_initiative" || true
fi
