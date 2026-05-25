#!/bin/bash
# ccpm-fetch-review-comments.sh — Coordinator: list **unresolved** review
# threads on the open PR for `initiative/<initiative>`, as a JSON array
# the LLM phase doc can iterate over.
#
# Usage:
#   bash ccpm-fetch-review-comments.sh <initiative>
#
# Output (stdout, JSON array; one entry per unresolved review thread):
#   [
#     {
#       "thread_id":         "<GraphQL node id>",
#       "root_comment_id":   <int — REST id of the first comment in thread>,
#       "path":              "<file path>",
#       "line":              <int|null>,
#       "comments": [
#         { "id": <int>, "body": "...", "author": "<login>", "url": "..." },
#         ...
#       ]
#     },
#     ...
#   ]
#
# Resolution status is fetched via GraphQL (REST `/comments` does not
# expose `isResolved`). Resolved threads are filtered out.
#
# Exit status:
#   0   Success (emits JSON; may be `[]` if no unresolved threads).
#   1   Validation error, no PR found, or `gh` failure.
#   2   Mode detection error.
#   1-3 (from gh-verify) gh CLI / auth / repo-access failure.
#
# IMPORTANT: Caller must cd to the git project root before invoking.

set -eu

_self_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_self_dir/lib/coordinator-lib.sh"

case "${1:-}" in
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
    ;;
esac
_initiative="${1:-}"
if [ -z "$_initiative" ]; then
  echo "ccpm-fetch-review-comments: usage: bash ccpm-fetch-review-comments.sh <initiative>" >&2
  exit 1
fi

_initiative_file=".ccpm/initiatives/$_initiative/$_initiative.md"
if [ ! -f "$_initiative_file" ]; then
  echo "ccpm-fetch-review-comments: initiative file not found: $_initiative_file" >&2
  exit 1
fi

# Preflight: gh-verify (writes status to stderr so stdout stays JSON-clean).
bash "$_self_dir/ccpm-gh-verify.sh" >&2

_branch="initiative/$_initiative"
_pr="$(gh pr list --head "$_branch" --state open --json number --jq '.[0].number // empty')"
if [ -z "$_pr" ]; then
  echo "ccpm-fetch-review-comments: no PR found for branch $_branch; push and create one first" >&2
  exit 1
fi

_repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
_owner="${_repo%%/*}"
_name="${_repo#*/}"

# Write the GraphQL query to a temp file — keeps quoting straightforward
# and avoids inlining the multi-line query into shell command substitution.
_query_file="$(mktemp)"
trap 'rm -f "$_query_file"' EXIT
cat > "$_query_file" <<'GRAPHQL'
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      reviewThreads(first:100){
        nodes{
          id
          isResolved
          comments(first:100){
            nodes{
              databaseId
              path
              line
              body
              author{login}
              url
            }
          }
        }
      }
    }
  }
}
GRAPHQL

gh api graphql \
  -F owner="$_owner" \
  -F name="$_name" \
  -F number="$_pr" \
  -F query=@"$_query_file" \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | {
            thread_id: .id,
            root_comment_id: (.comments.nodes[0].databaseId),
            path: .comments.nodes[0].path,
            line: .comments.nodes[0].line,
            comments: [.comments.nodes[]
                       | { id: .databaseId, body, author: .author.login, url }]
          }]'
