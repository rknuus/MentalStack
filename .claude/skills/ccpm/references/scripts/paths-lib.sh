#!/bin/bash
# paths-lib.sh — Reusable functions for resolving .ccpm/ directory paths.
# Source this file; do not execute directly.
#
# All functions use the pm_ prefix for namespacing.
# Functions echo paths only — no side effects (no mkdir, no file creation).
#
# IMPORTANT: Callers must cd to the git root before sourcing this file.
# All paths returned are relative to the project root.

# ---------------------------------------------------------------------------
# pm_initiative_file <name>
#
# Returns the path to an initiative's markdown file.
# Example: pm_initiative_file "auth" → .ccpm/initiatives/auth.md
# ---------------------------------------------------------------------------
pm_initiative_file() {
  local name="$1"
  echo ".ccpm/initiatives/${name}.md"
}

# ---------------------------------------------------------------------------
# pm_initiative_dir <name>
#
# Returns the path to an initiative's directory.
# Example: pm_initiative_dir "auth" → .ccpm/initiatives/auth/
# ---------------------------------------------------------------------------
pm_initiative_dir() {
  local name="$1"
  echo ".ccpm/initiatives/${name}/"
}

# ---------------------------------------------------------------------------
# pm_archive_dir <name>
#
# Returns the path to an archived initiative's directory.
# Example: pm_archive_dir "auth" → .ccpm/archive/auth/
# ---------------------------------------------------------------------------
pm_archive_dir() {
  local name="$1"
  echo ".ccpm/archive/${name}/"
}

# ---------------------------------------------------------------------------
# pm_epic_dir <initiative> <epic>
#
# Returns the path to an epic's directory under an initiative.
# Example: pm_epic_dir "auth" "login-flow" → .ccpm/initiatives/auth/login-flow/
# ---------------------------------------------------------------------------
pm_epic_dir() {
  local initiative="$1"
  local epic="$2"
  echo ".ccpm/initiatives/${initiative}/${epic}/"
}

# ---------------------------------------------------------------------------
# pm_epic_file <initiative> <epic>
#
# Returns the path to an epic's markdown file under an initiative.
# Example: pm_epic_file "auth" "login-flow" → .ccpm/initiatives/auth/login-flow/epic.md
# ---------------------------------------------------------------------------
pm_epic_file() {
  local initiative="$1"
  local epic="$2"
  echo ".ccpm/initiatives/${initiative}/${epic}/epic.md"
}

# ---------------------------------------------------------------------------
# pm_task_file <initiative> <epic> <id>
#
# Returns the path to a task file under an epic.
# Example: pm_task_file "auth" "login-flow" "42" → .ccpm/initiatives/auth/login-flow/42.md
# ---------------------------------------------------------------------------
pm_task_file() {
  local initiative="$1"
  local epic="$2"
  local id="$3"
  echo ".ccpm/initiatives/${initiative}/${epic}/${id}.md"
}

# ---------------------------------------------------------------------------
# pm_find_epic <epic>
#
# Resolves the location of an epic directory by searching the nested
# layout (.ccpm/initiatives/*/<epic>/).
#
# Returns:
#   - Directory if .ccpm/initiatives/*/<epic>/epic.md exists
#   - Default path for creation if it does not exist
# ---------------------------------------------------------------------------
pm_find_epic() {
  local epic="$1"

  # Check new layout: .ccpm/initiatives/*/<epic>/epic.md
  local match
  for match in .ccpm/initiatives/*/"${epic}"/epic.md; do
    if [ -f "$match" ]; then
      # Strip /epic.md to return the directory
      echo "${match%/epic.md}/"
      return 0
    fi
  done

  # Check archive: .ccpm/archive/*/<epic>/epic.md
  for match in .ccpm/archive/*/"${epic}"/epic.md; do
    if [ -f "$match" ]; then
      echo "${match%/epic.md}/"
      return 0
    fi
  done

  # Not found — return default path for creation.
  # Use the first initiative directory found, or fall back to <epic>/<epic>/.
  local first_initiative
  for first_initiative in .ccpm/initiatives/*/; do
    if [ -d "$first_initiative" ]; then
      local initiative_name
      initiative_name="$(basename "$first_initiative")"
      echo ".ccpm/initiatives/${initiative_name}/${epic}/"
      return 0
    fi
  done

  # No initiatives exist at all — use epic name as both initiative and epic
  echo ".ccpm/initiatives/${epic}/${epic}/"
}
