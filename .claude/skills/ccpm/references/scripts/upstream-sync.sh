#!/bin/bash
set -euo pipefail

# upstream-sync.sh — Semi-automate syncing fork with upstream CCPM
#
# Usage:
#   bash upstream-sync.sh <upstream-ref> [--apply]
#
# By default runs in dry-run mode (shows what would change).
# Pass --apply to actually copy transformed files.

UPSTREAM_REF="${1:-}"
APPLY_MODE=false
[ "${2:-}" = "--apply" ] && APPLY_MODE=true

if [ -z "$UPSTREAM_REF" ]; then
  echo "Usage: upstream-sync.sh <upstream-ref> [--apply]"
  echo "  upstream-ref: git ref (e.g., upstream-origin/main, a commit SHA)"
  echo "  --apply: actually copy files (default: dry-run)"
  exit 1
fi

# --- File classifications ---

# Upstream files (relative to skill/ccpm/ in upstream)
UPSTREAM_FILES=(
  "SKILL.md"
  "references/plan.md"
  "references/structure.md"
  "references/conventions.md"
  "references/execute.md"
  "references/sync.md"
  "references/track.md"
  "references/scripts/blocked.sh"
  "references/scripts/epic-list.sh"
  "references/scripts/epic-show.sh"
  "references/scripts/epic-status.sh"
  "references/scripts/help.sh"
  "references/scripts/in-progress.sh"
  "references/scripts/init.sh"
  "references/scripts/next.sh"
  "references/scripts/prd-list.sh"
  "references/scripts/prd-status.sh"
  "references/scripts/search.sh"
  "references/scripts/standup.sh"
  "references/scripts/status.sh"
  "references/scripts/validate.sh"
)

# Category A: auto-sync (path-only changes from upstream)
CAT_A=(
  "references/scripts/blocked.sh"
  "references/scripts/epic-show.sh"
  "references/scripts/epic-status.sh"
  "references/scripts/in-progress.sh"
  "references/scripts/next.sh"
  "references/track.md"
)

# Category B: auto-sync + review additions (path + small fork additions)
CAT_B=(
  "SKILL.md"
  "references/plan.md"
  "references/structure.md"
  "references/conventions.md"
  "references/scripts/init.sh"
  "references/scripts/help.sh"
  "references/scripts/search.sh"
  "references/scripts/standup.sh"
  "references/scripts/status.sh"
  "references/scripts/validate.sh"
  "references/scripts/epic-list.sh"
  "references/scripts/initiative-list.sh"
  "references/scripts/initiative-status.sh"
)

# Category C: manual review only (structural fork modifications)
CAT_C=(
  "references/execute.md"
  "references/sync.md"
)

# Fork-only files (no upstream equivalent)
FORK_ONLY=(
  "references/initiative.md"
  "references/context.md"
  "references/scripts/ccpm-find.sh"
  "references/scripts/ccpm-git-info.sh"
  "references/scripts/paths-lib.sh"
  "references/scripts/upstream-sync.sh"
)

# --- Helpers ---

get_category() {
  local file="$1"
  for f in "${CAT_A[@]}"; do [ "$f" = "$file" ] && echo "A" && return; done
  for f in "${CAT_B[@]}"; do [ "$f" = "$file" ] && echo "B" && return; done
  for f in "${CAT_C[@]}"; do [ "$f" = "$file" ] && echo "C" && return; done
  echo "?"
}

# Map upstream filename to fork filename (handles renames)
upstream_to_fork() {
  local file="$1"
  file="${file/prd-list.sh/initiative-list.sh}"
  file="${file/prd-status.sh/initiative-status.sh}"
  echo "$file"
}

# Apply path transforms to a file via sed (writes to stdout)
apply_transforms() {
  sed \
    -e 's|\.claude/prds/|.ccpm/initiatives/|g' \
    -e 's|\.claude/epics/|.ccpm/initiatives/|g' \
    -e 's|prd-list|initiative-list|g' \
    -e 's|prd-status|initiative-status|g' \
    -e 's|PRDs|Initiatives|g' \
    -e 's|PRD|Initiative|g' \
    -e 's|find \(\.ccpm/initiatives\)|bash "${SKILL_ROOT:-.claude/skills/ccpm}/references/scripts/ccpm-find.sh" \1|g' \
    -e 's|find \(\.claude/\)|bash "${SKILL_ROOT:-.claude/skills/ccpm}/references/scripts/ccpm-find.sh" \1|g'
}

# --- Main ---

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

FORK_ROOT="skill/ccpm"

echo "Upstream Sync Report"
echo "===================="
echo "Ref: $UPSTREAM_REF"
echo "Mode: $( $APPLY_MODE && echo "APPLY" || echo "dry-run" )"
echo ""

copied=0
skipped=0
up_to_date=0
manual_review=0
failed=0

for upstream_file in "${UPSTREAM_FILES[@]}"; do
  fork_file=$(upstream_to_fork "$upstream_file")
  cat_label=$(get_category "$fork_file")
  fork_path="$FORK_ROOT/$fork_file"

  # Extract file from upstream ref
  upstream_tmp="$TMPDIR/upstream_raw"
  if ! git show "$UPSTREAM_REF:skill/ccpm/$upstream_file" > "$upstream_tmp" 2>/dev/null; then
    echo "  ❌ [$cat_label] $fork_file — not found at $UPSTREAM_REF"
    ((failed++))
    continue
  fi

  # Apply transforms
  transformed_tmp="$TMPDIR/transformed"
  apply_transforms < "$upstream_tmp" > "$transformed_tmp"

  # Compare with current fork version
  if [ ! -f "$fork_path" ]; then
    lines=$(wc -l < "$transformed_tmp" | tr -d ' ')
    echo "  ➕ [$cat_label] $fork_file — NEW ($lines lines)"
    if $APPLY_MODE && [ "$cat_label" != "C" ]; then
      mkdir -p "$(dirname "$fork_path")"
      cp "$transformed_tmp" "$fork_path"
      ((copied++))
    elif $APPLY_MODE && [ "$cat_label" = "C" ]; then
      echo "     ⚠️  MANUAL REVIEW NEEDED — skipped"
      ((manual_review++))
    fi
    continue
  fi

  if diff -q "$transformed_tmp" "$fork_path" > /dev/null 2>&1; then
    echo "  ✅ [$cat_label] $fork_file — up to date"
    ((up_to_date++))
    continue
  fi

  # Files differ
  added=$(diff "$fork_path" "$transformed_tmp" 2>/dev/null | grep -c "^>" || true)
  removed=$(diff "$fork_path" "$transformed_tmp" 2>/dev/null | grep -c "^<" || true)

  if [ "$cat_label" = "C" ]; then
    echo "  ⚠️  [C] $fork_file — MANUAL REVIEW NEEDED (+$added/-$removed)"
    echo "     --- diff (fork vs transformed upstream) ---"
    diff -u "$fork_path" "$transformed_tmp" | head -40 || true
    echo "     --- end diff ---"
    echo ""
    ((manual_review++))
    if $APPLY_MODE; then
      echo "     Skipped (Category C requires manual review)"
      ((skipped++))
    fi
  else
    echo "  🔄 [$cat_label] $fork_file — changed (+$added/-$removed)"
    if $APPLY_MODE; then
      cp "$transformed_tmp" "$fork_path"
      ((copied++))
    fi
  fi
done

# Report fork-only files
echo ""
echo "Fork-Only Files"
echo "---------------"
for file in "${FORK_ONLY[@]}"; do
  path="$FORK_ROOT/$file"
  if [ -f "$path" ]; then
    echo "  📄 $file — fork-only (no upstream equivalent)"
  else
    echo "  📄 $file — fork-only (not yet created)"
  fi
done

# Summary
echo ""
echo "Summary"
echo "-------"
echo "  Up to date:     $up_to_date"
if $APPLY_MODE; then
  echo "  Copied:         $copied"
  echo "  Skipped (C):    $skipped"
else
  changed=$((${#UPSTREAM_FILES[@]} - up_to_date - failed))
  echo "  Changed:        $changed"
fi
echo "  Manual review:  $manual_review"
echo "  Not found:      $failed"
echo "  Fork-only:      ${#FORK_ONLY[@]}"

if ! $APPLY_MODE && [ $((${#UPSTREAM_FILES[@]} - up_to_date - failed)) -gt 0 ]; then
  echo ""
  echo "Run with --apply to copy Category A and B files."
  echo "Category C files (execute.md, sync.md) always require manual review."
fi

exit 0
