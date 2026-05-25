#!/bin/bash
# ccpm-merge-initiative.sh — Coordinator: merge an initiative into main.
#
# Usage:
#   bash ccpm-merge-initiative.sh <initiative> [--force-incomplete] [--json]
#
# Behavior (in order):
#   1. Pre-checks: branch initiative/<i> exists; working tree clean; all
#      epics under .ccpm/initiatives/<i>/*/epic.md have status: completed
#      (unless --force-incomplete is passed).
#   2. Mode detection.
#   3. `git checkout initiative/<i>`; `git pull origin initiative/<i>`
#      gated on ONLINE.
#   4. Fetch latest main and rebase initiative onto it. On conflict,
#      `git rebase --abort` and exit 1 with a clear error.
#   5. `git checkout main`; `git pull origin main` gated on ONLINE.
#   6. `git merge --ff-only initiative/<i> -m "Merge initiative: <i>"`.
#   7. If sibling worktree at ../<repo>-<i> exists: `git worktree remove`
#      BEFORE `git branch -D` (per FR-4: branch deletion fails when the
#      branch is checked out in another worktree).
#   8. `git branch -D initiative/<i>`.
#   9. `git push origin --delete initiative/<i>` gated on ONLINE
#      (failure reported, not blocking).
#  10. Archive: `mv .ccpm/initiatives/<i> .ccpm/archive/<i>` (always
#      performed when the directory exists; the move is working-tree only
#      when .ccpm/ is gitignored).
#
# Exit status:
#   0   Success.
#   1   Validation error or rebase/merge conflict.
#   2   Mode detection error.

set -eu

_self_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_self_dir/lib/coordinator-lib.sh"

_force_incomplete=0
_positional=()

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      export COORD_OUTPUT_MODE=json
      shift
      ;;
    --force-incomplete)
      _force_incomplete=1
      shift
      ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 1
      ;;
    *)
      _positional+=("$1")
      shift
      ;;
  esac
done

if [ "${#_positional[@]}" -lt 1 ]; then
  echo "ccpm-merge-initiative: usage: bash ccpm-merge-initiative.sh <initiative> [--force-incomplete] [--json]" >&2
  exit 1
fi
_initiative="${_positional[0]}"
_branch="initiative/$_initiative"
_init_dir=".ccpm/initiatives/$_initiative"

# Pre-check: branch exists.
if ! git rev-parse --verify --quiet "refs/heads/$_branch" >/dev/null; then
  echo "ccpm-merge-initiative: branch $_branch not found" >&2
  exit 1
fi

# Pre-check: no uncommitted changes OUTSIDE the initiative directory.
# Untracked/uncommitted files inside .ccpm/initiatives/<initiative>/ are part
# of the merge's natural scope (the initiative branch's commits will populate
# them, or git's ff-only check will catch real overlap conflicts). Changes
# outside that directory would mean the user has unrelated WIP that the
# merge should not silently fast-forward over.
_outside_dirty="$(git status --porcelain --untracked-files=all | grep -vE "\\.ccpm/initiatives/${_initiative}(/|$)" 2>/dev/null || true)"
if [ -n "$_outside_dirty" ]; then
  echo "ccpm-merge-initiative: working tree has uncommitted changes outside .ccpm/initiatives/$_initiative/; commit, stash, or discard before merging" >&2
  echo "$_outside_dirty" >&2
  exit 1
fi

# Pre-check: all epics completed.
_incomplete=()
shopt -s nullglob
for _epic_file in "$_init_dir"/*/epic.md; do
  _status="$(grep -E '^status:[[:space:]]*' "$_epic_file" \
    | head -n 1 \
    | sed 's/^status:[[:space:]]*//' \
    | tr -d '[:space:]')"
  if [ "$_status" != "completed" ]; then
    _incomplete+=("$(basename "$(dirname "$_epic_file")"):${_status:-<missing>}")
  fi
done
shopt -u nullglob

if [ "${#_incomplete[@]}" -gt 0 ] && [ "$_force_incomplete" -ne 1 ]; then
  echo "ccpm-merge-initiative: not all epics are completed: ${_incomplete[*]}" >&2
  echo "ccpm-merge-initiative: pass --force-incomplete to merge anyway" >&2
  exit 1
fi

if ! coord_init "$_initiative"; then
  exit $?
fi

_repo_root="$(git rev-parse --show-toplevel)"
_repo_basename="$(basename "$_repo_root")"
_worktree_path="$(cd "$_repo_root/.." && pwd)/$_repo_basename-$_initiative"

# Identify which working tree owns the initiative branch's checkout. When a
# sibling worktree exists, the initiative branch is checked out there and the
# main repo cannot also check it out; rebase must run in the worktree's cwd.
if [ -d "$_worktree_path" ]; then
  _init_work_dir="$_worktree_path"
else
  _init_work_dir="$_repo_root"
  git checkout -q "$_branch"
fi

# Step 3-4: rebase initiative onto latest main.
if [ "${ONLINE:-false}" = "true" ]; then
  ( cd "$_init_work_dir" && git pull -q --ff-only origin "$_branch" 2>/dev/null ) || true
  git fetch -q origin main 2>/dev/null || true
fi

if ! ( cd "$_init_work_dir" && git rebase main >/dev/null 2>&1 ); then
  ( cd "$_init_work_dir" && git rebase --abort 2>/dev/null ) || true
  echo "ccpm-merge-initiative: rebase of $_branch onto main failed; resolve conflicts manually then re-run" >&2
  exit 1
fi
coord_status "rebased: $_branch onto main"

# Step 5-6: ff-only merge to main.
if [ "$_init_work_dir" = "$_repo_root" ]; then
  git checkout -q main
fi
if [ "${ONLINE:-false}" = "true" ]; then
  git pull -q --ff-only origin main 2>/dev/null || true
fi

if ! git merge --ff-only "$_branch" -m "Merge initiative: $_initiative" >/dev/null; then
  echo "ccpm-merge-initiative: ff-only merge of $_branch into main failed" >&2
  exit 1
fi
coord_status "merged: $_branch -> main"

# Step 7-8: cleanup. ORDER strictly enforced — worktree-remove BEFORE
# branch-D (per FR-4: `git branch -D` fails on a branch checked out in
# another worktree).
if [ -d "$_worktree_path" ]; then
  git worktree remove -f "$_worktree_path"
  coord_status "worktree-removed: $_worktree_path"
fi

git branch -D "$_branch" >/dev/null
coord_status "branch-deleted: $_branch"

# Step 9: push delete.
if [ "${ONLINE:-false}" = "true" ]; then
  if git push -q origin --delete "$_branch" 2>/dev/null; then
    coord_status "remote-branch-deleted: $_branch"
  else
    coord_status "remote-branch-delete-failed: $_branch (not blocking)"
  fi
fi

# Step 10: archive.
if [ -d "$_init_dir" ]; then
  mkdir -p .ccpm/archive
  mv "$_init_dir" ".ccpm/archive/$_initiative"
  coord_status "archived: .ccpm/archive/$_initiative"
fi
