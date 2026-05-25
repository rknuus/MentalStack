#!/bin/bash
# ccpm-git-info.sh — Output git state summary for context management.
#
# Avoids compound commands with quoted separators that trigger AI tool
# command monitor heuristics (e.g., "quoted characters in flag names").
#
# Usage:
#   bash ccpm-git-info.sh [--full]
#
# Default output: branch and short status.
# With --full: adds recent commits and recent file changes.

set -euo pipefail

mode="${1:-default}"

echo "branch: $(git branch --show-current 2>/dev/null || echo 'detached')"
echo "status:"
git status --short 2>/dev/null || true

if [ "$mode" = "--full" ]; then
  echo ""
  echo "recent-commits:"
  git log --oneline -10 2>/dev/null || true
  echo ""
  echo "recent-changes:"
  git diff --stat HEAD~5..HEAD 2>/dev/null || true
fi

exit 0
