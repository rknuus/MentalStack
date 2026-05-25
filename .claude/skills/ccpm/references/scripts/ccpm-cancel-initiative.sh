#!/bin/bash
# ccpm-cancel-initiative.sh — Coordinator: cancel an initiative.
#
# Usage:
#   bash ccpm-cancel-initiative.sh <initiative> [--archive] [--reason <text>] [--json]
#
# Behavior:
#   - Pre-check: working tree clean (block if dirty; user must commit, stash,
#     or discard first per existing convention).
#   - `git checkout main`.
#   - If the sibling worktree exists at `../<repo>-<initiative>`, remove it
#     BEFORE branch deletion (per FR-4: `git branch -D` on a branch still
#     checked out in a worktree fails).
#   - `git branch -D initiative/<initiative>`.
#   - `git push origin --delete initiative/<initiative>` gated on ONLINE.
#   - Final step:
#       --archive (default off): rm -rf .ccpm/initiatives/<initiative>
#       --archive supplied:      mv .ccpm/initiatives/<initiative>
#                                   .ccpm/archive/<initiative>; injects
#                                   `cancelled: true` (and `cancel_reason: …`
#                                   when --reason was passed) into the
#                                   initiative file's frontmatter before move.
#
# Exit status:
#   0   Success.
#   1   Validation error (dirty tree, missing branch, etc.).
#   2   Mode detection error.

set -eu

_self_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_self_dir/lib/coordinator-lib.sh"

_archive=0
_reason=""
_positional=()

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      export COORD_OUTPUT_MODE=json
      shift
      ;;
    --archive)
      _archive=1
      shift
      ;;
    --reason)
      _reason="${2:-}"
      shift 2
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
  echo "ccpm-cancel-initiative: usage: bash ccpm-cancel-initiative.sh <initiative> [--archive] [--reason <text>] [--json]" >&2
  exit 1
fi
_initiative="${_positional[0]}"
_branch="initiative/$_initiative"
_init_dir=".ccpm/initiatives/$_initiative"

# Pre-check: no uncommitted changes OUTSIDE the initiative directory.
# Changes inside .ccpm/initiatives/<initiative>/ are about to be deleted/
# archived anyway, so they don't need to be committed first. Changes outside
# (working code, sibling initiatives, config) would be lost or surprise the
# user, so they block.
_outside_dirty="$(git status --porcelain --untracked-files=all | grep -vE "\\.ccpm/initiatives/${_initiative}(/|$)" 2>/dev/null || true)"
if [ -n "$_outside_dirty" ]; then
  echo "ccpm-cancel-initiative: working tree has uncommitted changes outside .ccpm/initiatives/$_initiative/; commit, stash, or discard before cancelling" >&2
  echo "$_outside_dirty" >&2
  exit 1
fi

# Pre-check: branch exists.
if ! git rev-parse --verify --quiet "refs/heads/$_branch" >/dev/null; then
  echo "ccpm-cancel-initiative: branch $_branch not found" >&2
  exit 1
fi

if ! coord_init "$_initiative"; then
  exit $?
fi

_repo_root="$(git rev-parse --show-toplevel)"
_repo_basename="$(basename "$_repo_root")"
_worktree_path="$(cd "$_repo_root/.." && pwd)/$_repo_basename-$_initiative"

git checkout -q main

# Cleanup ORDER: worktree-remove BEFORE branch-D (per FR-4).
if [ -d "$_worktree_path" ]; then
  git worktree remove -f "$_worktree_path"
  coord_status "worktree-removed: $_worktree_path"
fi

git branch -D "$_branch" >/dev/null
coord_status "branch-deleted: $_branch"

if [ "${ONLINE:-false}" = "true" ]; then
  if git push -q origin --delete "$_branch" 2>/dev/null; then
    coord_status "remote-branch-deleted: $_branch"
  else
    coord_status "remote-branch-delete-failed: $_branch (not blocking)"
  fi
fi

# Final step: archive or delete.
if [ "$_archive" -eq 1 ]; then
  _init_file="$_init_dir/$_initiative.md"
  if [ -f "$_init_file" ]; then
    # Inject `cancelled: true` (and optional `cancel_reason:`) into frontmatter
    # by inserting before the closing `---` line.
    awk -v reason="$_reason" '
      /^---$/ {
        ++count
        if (count == 2) {
          print "cancelled: true"
          if (reason != "") print "cancel_reason: " reason
        }
      }
      { print }
    ' "$_init_file" > "$_init_file.new"
    mv "$_init_file.new" "$_init_file"
  fi
  mkdir -p .ccpm/archive
  mv "$_init_dir" ".ccpm/archive/$_initiative"
  coord_status "archived: .ccpm/archive/$_initiative"
else
  rm -rf "$_init_dir"
  coord_status "deleted: $_init_dir"
fi
