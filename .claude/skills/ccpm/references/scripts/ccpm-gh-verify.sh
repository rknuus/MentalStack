#!/bin/bash
# ccpm-gh-verify.sh — Coordinator: verify the `gh` CLI is installed,
# authenticated, and able to resolve the current repository.
#
# Used as a preflight by review-loop coordinators
# (ccpm-push-for-review.sh, ccpm-fetch-review-comments.sh,
# ccpm-reply-review-thread.sh).
#
# Usage:
#   bash ccpm-gh-verify.sh
#   bash ccpm-gh-verify.sh --json
#
# Failure modes (each emits a single-line, actionable message and exits
# non-zero so callers surface the cause without further parsing):
#   1   `gh` not on PATH
#   2   `gh` authenticated check failed (`gh auth status`)
#   3   `gh` cannot resolve current repository (e.g. wrong host, no access)
#
# Success: exits 0 and emits `coord_status "gh-verify: ok"`.
#
# IMPORTANT: Caller must cd to the git project root before invoking.

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

if ! command -v gh >/dev/null 2>&1; then
  coord_status "gh-verify: gh CLI not installed; install from https://cli.github.com"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  coord_status "gh-verify: gh not authenticated; run: gh auth login"
  exit 2
fi

if ! gh repo view --json nameWithOwner >/dev/null 2>&1; then
  coord_status "gh-verify: gh authenticated, but unable to resolve current repository"
  exit 3
fi

coord_status "gh-verify: ok"
