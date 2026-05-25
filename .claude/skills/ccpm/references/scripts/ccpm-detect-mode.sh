#!/bin/bash
# ccpm-detect-mode.sh — Project-mode detection (FR-1).
#
# Usage:
#   bash ccpm-detect-mode.sh <initiative>          KEY=VALUE form (eval-friendly)
#   bash ccpm-detect-mode.sh --json <initiative>   Single-line JSON object
#
# Outputs six flags:
#   CCPM_TRACKED      true|false   .ccpm/ is git-tracked
#   METHOD_DIR        <path>|""    architect dir (e.g. ".method") or empty
#   METHOD_TRACKED    true|false   METHOD_DIR is git-tracked (false when empty)
#   WORKTREE_ACTIVE   true|false   initiative has a sibling worktree checked out
#   ONLINE            true|false   `git ls-remote origin HEAD` succeeds
#   SYNC_ENABLED      true|false   `gh auth status` succeeds (or settings override)
#
# Resolution per FR-1: settings override (.ccpm/settings.yml) wins over
# auto-detection. ONLINE has no override (environmental). ONLINE and
# SYNC_ENABLED are independent: SYNC_ENABLED does NOT require ONLINE.
#
# Exit status:
#   0  success
#   2  METHOD_DIR multi-match failure (per FR-1) — multiple *.method
#      directories present and no method_dir override set
#
# IMPORTANT: Caller must cd to the git root before invoking. Paths are
# resolved relative to the project root.

set -eu

_settings_file=".ccpm/settings.yml"

# Trimmed value for a settings key. Empty if file missing or key absent.
_yaml_value() {
  [ -f "$_settings_file" ] || return 0
  grep -E "^$1[[:space:]]*:" "$_settings_file" 2>/dev/null \
    | head -n 1 \
    | sed "s/^$1[[:space:]]*:[[:space:]]*//" \
    | tr -d '[:space:]'
}

# Return 0 if the key is present (even with empty value); 1 otherwise.
_yaml_has() {
  [ -f "$_settings_file" ] || return 1
  grep -qE "^$1[[:space:]]*:" "$_settings_file"
}

# True iff the key is present AND its value is exactly "true".
_yaml_bool_true() {
  [ "$(_yaml_value "$1")" = "true" ]
}

# ---------------------------------------------------------------------------
# Per-flag helpers
# ---------------------------------------------------------------------------

_detect_method_dir() {
  if _yaml_has method_dir; then
    _yaml_value method_dir
    echo
    return 0
  fi

  # Glob *.method directories at repo root and filter to actual directories.
  entries=()
  shopt -s nullglob
  for entry in *.method; do
    [ -d "$entry" ] && entries+=("$entry")
  done
  shopt -u nullglob

  case "${#entries[@]}" in
    0) echo "" ;;
    1) echo "${entries[0]}" ;;
    *)
      echo "ccpm-detect-mode: multiple *.method directories found: ${entries[*]}; set 'method_dir:' in $_settings_file to disambiguate" >&2
      return 2
      ;;
  esac
}

_detect_ccpm_tracked() {
  if _yaml_has ccpm_tracked; then
    if _yaml_bool_true ccpm_tracked; then echo "true"; else echo "false"; fi
    return 0
  fi
  if git check-ignore -q .ccpm/; then echo "false"; else echo "true"; fi
}

_detect_method_tracked() {
  method_dir="$1"
  if [ -z "$method_dir" ]; then echo "false"; return 0; fi
  if _yaml_has method_tracked; then
    if _yaml_bool_true method_tracked; then echo "true"; else echo "false"; fi
    return 0
  fi
  if git check-ignore -q "$method_dir/"; then echo "false"; else echo "true"; fi
}

_detect_worktree_active() {
  initiative="$1"
  [ -n "$initiative" ] || { echo "false"; return 0; }

  frontmatter_file=".ccpm/initiatives/$initiative/$initiative.md"
  [ -f "$frontmatter_file" ] || { echo "false"; return 0; }

  fm_value=$(grep -E '^worktree[[:space:]]*:' "$frontmatter_file" \
    | head -n 1 \
    | sed 's/^worktree[[:space:]]*:[[:space:]]*//' \
    | tr -d '[:space:]')
  [ "$fm_value" = "true" ] || { echo "false"; return 0; }

  repo_root="$(git rev-parse --show-toplevel)"
  expected="$(basename "$repo_root")-$initiative"

  while IFS= read -r line; do
    [ "$(basename "$line")" = "$expected" ] && { echo "true"; return 0; }
  done < <(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10)}')

  echo "false"
}

_detect_online() {
  git remote get-url origin >/dev/null 2>&1 || { echo "false"; return 0; }
  git ls-remote --exit-code origin HEAD >/dev/null 2>&1 || { echo "false"; return 0; }
  echo "true"
}

_detect_sync_enabled() {
  if _yaml_has github_sync; then
    if _yaml_bool_true github_sync; then echo "true"; else echo "false"; fi
    return 0
  fi
  command -v gh >/dev/null 2>&1 || { echo "false"; return 0; }
  gh auth status >/dev/null 2>&1 || { echo "false"; return 0; }
  echo "true"
}

# ---------------------------------------------------------------------------
# Argument parsing & dispatch
# ---------------------------------------------------------------------------

_format=keyvalue
case "${1:-}" in
  --json)
    _format=json
    shift
    ;;
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
    ;;
esac
_initiative="${1:-}"

ccpm_tracked="$(_detect_ccpm_tracked)"
if ! method_dir="$(_detect_method_dir)"; then
  exit 2
fi
method_tracked="$(_detect_method_tracked "$method_dir")"
worktree_active="$(_detect_worktree_active "$_initiative")"
online="$(_detect_online)"
sync_enabled="$(_detect_sync_enabled)"

case "$_format" in
  keyvalue)
    cat <<EOF
CCPM_TRACKED=${ccpm_tracked}
METHOD_DIR=${method_dir}
METHOD_TRACKED=${method_tracked}
WORKTREE_ACTIVE=${worktree_active}
ONLINE=${online}
SYNC_ENABLED=${sync_enabled}
EOF
    ;;
  json)
    # Booleans as JSON booleans; method_dir as quoted string. Path values
    # don't contain JSON-special characters in practice.
    printf '{"ccpm_tracked":%s,"method_dir":"%s","method_tracked":%s,"worktree_active":%s,"online":%s,"sync_enabled":%s}\n' \
      "$ccpm_tracked" "$method_dir" "$method_tracked" "$worktree_active" "$online" "$sync_enabled"
    ;;
esac
