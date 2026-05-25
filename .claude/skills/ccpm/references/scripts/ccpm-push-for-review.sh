#!/bin/bash
# ccpm-push-for-review.sh — Coordinator: push the initiative branch to
# origin so a GitHub PR review can be performed.
#
# Wraps ccpm-push-branch.sh with a `gh` verification preflight and a
# distinct "ready for review" status line so downstream tooling can detect
# the review-loop entry point.
#
# Usage:
#   bash ccpm-push-for-review.sh <initiative>
#   bash ccpm-push-for-review.sh --json <initiative>
#
# Behavior:
#   1. Run ccpm-gh-verify.sh — abort with its exit code on failure.
#   2. Invoke ccpm-push-branch.sh <initiative> (with --json propagated).
#   3. On a successful push, emit `coord_status "review-push: ready"`.
#
# Idempotency: re-running after no new commits succeeds; the underlying
# `git push` is non-fast-forward-safe (no --force).
#
# Exit status:
#   0   Push succeeded (or skipped due to ONLINE=false; status line is
#       still propagated from ccpm-push-branch.sh).
#   1   Validation error or push failure.
#   2   Mode detection error.
#   1-3 (from gh-verify) gh CLI / auth / repo-access failure.

set -eu

_self_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_self_dir/lib/coordinator-lib.sh"

_json_mode=
case "${1:-}" in
  --json)
    export COORD_OUTPUT_MODE=json
    _json_mode=--json
    shift
    ;;
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
    ;;
esac
_initiative="${1:-}"
if [ -z "$_initiative" ]; then
  echo "ccpm-push-for-review: usage: bash ccpm-push-for-review.sh [--json] <initiative>" >&2
  exit 1
fi

_initiative_file=".ccpm/initiatives/$_initiative/$_initiative.md"
if [ ! -f "$_initiative_file" ]; then
  echo "ccpm-push-for-review: initiative file not found: $_initiative_file" >&2
  exit 1
fi

# Verify the local branch exists. The phase doc relies on this check so
# the agent never has to run a `git branch --list` itself.
_branch="initiative/$_initiative"
if ! git rev-parse --verify --quiet "refs/heads/$_branch" >/dev/null; then
  echo "ccpm-push-for-review: local branch not found: $_branch (implement the initiative first)" >&2
  exit 1
fi

# Verify a remote is configured. The review loop assumes a remote exists;
# silent ONLINE=false would emit a misleading "ready" status. Fail loudly
# so the agent gets an actionable error instead of guessing what to check.
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "ccpm-push-for-review: no 'origin' remote configured (set with: git remote add origin <url>)" >&2
  exit 1
fi

# Preflight: gh-verify. Pass --json through so its status output matches
# the caller's chosen mode.
if [ -n "$_json_mode" ]; then
  bash "$_self_dir/ccpm-gh-verify.sh" --json
else
  bash "$_self_dir/ccpm-gh-verify.sh"
fi

# Delegate the actual push to ccpm-push-branch.sh. It owns ONLINE gating
# and the "skipped: offline" status. For the review loop we treat ONLINE=false
# as an error: a "skipped" branch can't be reviewed on GitHub.
if [ -n "$_json_mode" ]; then
  _push_out="$(bash "$_self_dir/ccpm-push-branch.sh" --json "$_initiative")"
else
  _push_out="$(bash "$_self_dir/ccpm-push-branch.sh" "$_initiative")"
fi
printf '%s\n' "$_push_out"
case "$_push_out" in
  *skipped*)
    echo "ccpm-push-for-review: branch was not pushed (ONLINE=false). Resolve connectivity and retry." >&2
    exit 1
    ;;
esac

coord_status "review-push: ready"
