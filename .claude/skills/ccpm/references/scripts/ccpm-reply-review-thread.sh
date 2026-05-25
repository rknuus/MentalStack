#!/bin/bash
# ccpm-reply-review-thread.sh — Coordinator: post a reply to a PR review
# thread on the open PR for `initiative/<initiative>`.
#
# Usage:
#   bash ccpm-reply-review-thread.sh <initiative> <root-comment-id> <body-file>
#
# <root-comment-id> is the integer REST id of the first comment in the
# thread, as emitted by ccpm-fetch-review-comments.sh as `root_comment_id`.
#
# <body-file> is a file containing the reply body. Reading from a file
# keeps multi-line / special-character bodies safe — no inline shell
# quoting, no command substitution at the call site.
#
# Posts via REST: POST /repos/:o/:r/pulls/:n/comments/:cid/replies
# Does NOT mark the thread resolved — the user decides resolution.
#
# Exit status:
#   0   Reply posted (emits `coord_status "thread-reply-posted: <id>"`).
#   1   Validation error, no PR found, or `gh` failure.
#   1-3 (from gh-verify) gh CLI / auth / repo-access failure.
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

_initiative="${1:-}"
_root_comment_id="${2:-}"
_body_file="${3:-}"
if [ -z "$_initiative" ] || [ -z "$_root_comment_id" ] || [ -z "$_body_file" ]; then
  echo "ccpm-reply-review-thread: usage: bash ccpm-reply-review-thread.sh [--json] <initiative> <root-comment-id> <body-file>" >&2
  exit 1
fi
if [ ! -f "$_body_file" ]; then
  echo "ccpm-reply-review-thread: body file not found: $_body_file" >&2
  exit 1
fi

_initiative_file=".ccpm/initiatives/$_initiative/$_initiative.md"
if [ ! -f "$_initiative_file" ]; then
  echo "ccpm-reply-review-thread: initiative file not found: $_initiative_file" >&2
  exit 1
fi

bash "$_self_dir/ccpm-gh-verify.sh" >&2

_branch="initiative/$_initiative"
_pr="$(gh pr list --head "$_branch" --state open --json number --jq '.[0].number // empty')"
if [ -z "$_pr" ]; then
  echo "ccpm-reply-review-thread: no PR found for branch $_branch; push and create one first" >&2
  exit 1
fi

_repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"

# Read the body file in-process and pass as a literal string field. Do NOT
# use `gh api -F body=@<file>` here: gh treats any `@<file>` value as a
# file-upload trigger and switches the request to multipart/form-data,
# which GitHub's review-thread replies endpoint rejects with HTTP 422.
# `-f body=<string>` keeps the request as application/json (the gh default
# for POST), and gh handles JSON-escaping of newlines / quotes / backslashes.
_body_content="$(cat "$_body_file")"
gh api -X POST \
  "repos/$_repo/pulls/$_pr/comments/$_root_comment_id/replies" \
  -f body="$_body_content" >/dev/null

coord_status "thread-reply-posted: $_root_comment_id"
