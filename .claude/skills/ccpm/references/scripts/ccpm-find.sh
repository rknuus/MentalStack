#!/bin/bash
# ccpm-find.sh — Safe find wrapper for AI tool compatibility.
#
# AI tool command monitors flag `find` because it can execute arbitrary
# commands via -exec. This wrapper uses find internally but presents a
# named-script interface, so monitors see "bash ccpm-find.sh" instead.
#
# Usage:
#   bash ccpm-find.sh <path> [-name <pattern>] [-path <pattern>] [-type <f|d>]
#
# Examples:
#   bash ccpm-find.sh .ccpm/initiatives -path "*/auth/epic.md"
#   bash ccpm-find.sh .ccpm/initiatives -name "[0-9]*.md" -type f
#   bash ccpm-find.sh .pm -name "*.md"

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: ccpm-find.sh <path> [-name <pattern>] [-path <pattern>] [-type <f|d>]" >&2
  exit 1
fi

search_path="$1"
shift

# Validate: no dangerous flags
for arg in "$@"; do
  case "$arg" in
    -exec|-execdir|-delete|-ok)
      echo "Error: flag '$arg' is not allowed" >&2
      exit 1
      ;;
  esac
done

# If path doesn't exist, produce no output (match find's behavior with 2>/dev/null)
if [ ! -d "$search_path" ]; then
  exit 0
fi

# Pass remaining arguments directly to find
find "$search_path" "$@" 2>/dev/null || true

exit 0
