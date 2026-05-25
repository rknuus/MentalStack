#!/bin/bash
# ccpm-commit-review-fix.sh — Coordinator: commit a review-comment fix
# during the GitHub PR review loop.
#
# Usage:
#   bash ccpm-commit-review-fix.sh <initiative> \
#        --message-file <path> [--push] [--json] -- <code-path…>
#
# The agent pre-writes a commit-message file. Subject (first non-empty line)
# must start with `Address review` so review-fix commits are searchable in
# `git log`. The coordinator runs the FR-8 atomic commit recipe via
# `coord_commit` and optionally pushes the initiative branch when `--push`
# is given (gated on ONLINE).
#
# Behavior:
#   - On commit success: the agent's --message-file is removed.
#   - On commit failure: the agent's --message-file is preserved for
#     diagnosis (the agent can inspect, fix, and retry).
#   - Empty diff: treated as no-op (returns 0), per coord_commit.
#
# Exit status:
#   0   Commit created OR empty diff (no-op).
#   1   Validation error (missing args, bad subject, missing message file,
#       commit failure).
#   2   Mode detection error.
#
# IMPORTANT: Caller must cd to the git project root before invoking.

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

if [ "${#_positional[@]}" -lt 1 ]; then
  echo "ccpm-commit-review-fix: usage: bash ccpm-commit-review-fix.sh <initiative> --message-file <path> [--push] [--json] -- <code-path...>" >&2
  exit 1
fi
_initiative="${_positional[0]}"

if [ -z "$_message_file" ]; then
  echo "ccpm-commit-review-fix: --message-file is required" >&2
  exit 1
fi
if [ ! -f "$_message_file" ]; then
  echo "ccpm-commit-review-fix: message file not found: $_message_file" >&2
  exit 1
fi

if [ "${#_code_paths[@]}" -eq 0 ]; then
  echo "ccpm-commit-review-fix: at least one code-path required after --" >&2
  exit 1
fi

_initiative_file=".ccpm/initiatives/$_initiative/$_initiative.md"
if [ ! -f "$_initiative_file" ]; then
  echo "ccpm-commit-review-fix: initiative file not found: $_initiative_file" >&2
  exit 1
fi

# Validate the subject line: first non-empty line must start with
# "Address review ". This makes review-fix commits findable via
# `git log --grep '^Address review'`.
_subject="$(grep -m 1 -v '^[[:space:]]*$' "$_message_file" 2>/dev/null || true)"
if ! echo "$_subject" | grep -qE '^Address review '; then
  echo "ccpm-commit-review-fix: message subject must start with 'Address review ' (got: '$_subject')" >&2
  exit 1
fi

if ! coord_init "$_initiative"; then
  exit $?
fi

# Backup the message file so we can restore it on commit failure.
# coord_commit unconditionally removes its <msg-file> argument; passing the
# agent's file directly would lose it on a real error.
_msg_tmp="$(mktemp -t ccpm-commit-review-fix.XXXXXX)"
cp "$_message_file" "$_msg_tmp"

if coord_commit "$_msg_tmp" "${_code_paths[@]}"; then
  rm -f "$_message_file"
else
  rm -f "$_msg_tmp"
  exit 1
fi

if [ "$_push" -eq 1 ]; then
  coord_push_branch "initiative/$_initiative" || true
fi
