#!/bin/bash
# ccpm-create-branch.sh — Coordinator: create the initiative branch (and
# optionally the sibling worktree) per the canonical recipe.
#
# Usage:
#   bash ccpm-create-branch.sh <initiative>
#   bash ccpm-create-branch.sh --json <initiative>
#
# Pre-checks:
#   - `main` branch must exist.
#
# Dirty-tree handling: uncommitted changes on `main` are NOT blocked. The
# canonical CCPM flow is "write initiative/epic files on main → create
# initiative branch (changes carry over) → commit on the new branch." Git's
# own checkout/branch semantics handle the carry-over correctly. If a real
# checkout conflict surfaces, git reports it and the script aborts naturally.
#
# Steps (in order):
#   1. Run mode detection.
#   2. `git checkout main` (idempotent).
#   3. `git pull origin main` if ONLINE=true.
#   4. If branch `initiative/<initiative>` exists → checkout it; status note
#      reports `branch-exists`. Otherwise:
#         - If frontmatter `worktree: true`: `git branch initiative/<i> main`
#           (create only, don't check out — leaves main as current branch).
#         - Else: `git checkout -b initiative/<i>` from main.
#   5. If `worktree: true` and the sibling worktree path doesn't exist:
#      `git worktree add ../<repo-basename>-<initiative> initiative/<i>`.
#   6. `git push -u origin initiative/<i>` if ONLINE=true.
#
# Exit status:
#   0   Success (branch created, switched, or already existed).
#   1   Validation error (dirty tree, missing main, etc.).
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
  echo "ccpm-create-branch: usage: bash ccpm-create-branch.sh [--json] <initiative>" >&2
  exit 1
fi

_initiative_file=".ccpm/initiatives/$_initiative/$_initiative.md"
if [ ! -f "$_initiative_file" ]; then
  echo "ccpm-create-branch: initiative file not found: $_initiative_file" >&2
  exit 1
fi

# Pre-check: main branch exists.
if ! git rev-parse --verify --quiet refs/heads/main >/dev/null; then
  echo "ccpm-create-branch: 'main' branch not found in this repository" >&2
  exit 1
fi

if ! coord_init "$_initiative"; then
  exit $?
fi

_branch="initiative/$_initiative"
_repo_root="$(git rev-parse --show-toplevel)"
_repo_basename="$(basename "$_repo_root")"
_worktree_path="$(cd "$_repo_root/.." && pwd)/$_repo_basename-$_initiative"

# Read frontmatter `worktree:` value (true/false).
_worktree_enabled="$(grep -E '^worktree:[[:space:]]*' "$_initiative_file" \
  | head -n 1 \
  | sed 's/^worktree:[[:space:]]*//' \
  | tr -d '[:space:]')"

git checkout -q main

if [ "${ONLINE:-false}" = "true" ]; then
  git pull -q --ff-only origin main 2>/dev/null || true
fi

_branch_existed=0
if git rev-parse --verify --quiet "refs/heads/$_branch" >/dev/null; then
  _branch_existed=1
fi

if [ "$_branch_existed" -eq 1 ]; then
  coord_status "branch-exists: $_branch"
  if [ "$_worktree_enabled" = "true" ]; then
    if [ ! -d "$_worktree_path" ]; then
      git worktree add -q "$_worktree_path" "$_branch"
      coord_status "worktree-created: $_worktree_path"
    fi
  else
    git checkout -q "$_branch"
  fi
else
  if [ "$_worktree_enabled" = "true" ]; then
    git branch "$_branch" main
    git worktree add -q "$_worktree_path" "$_branch"
    coord_status "branch-created: $_branch"
    coord_status "worktree-created: $_worktree_path"
  else
    git checkout -q -b "$_branch"
    coord_status "branch-created: $_branch"
  fi
fi

if [ "${ONLINE:-false}" = "true" ]; then
  if git push -q -u origin "$_branch" 2>/dev/null; then
    coord_status "pushed: $_branch"
  else
    coord_status "push-failed: $_branch (not blocking)"
  fi
fi
