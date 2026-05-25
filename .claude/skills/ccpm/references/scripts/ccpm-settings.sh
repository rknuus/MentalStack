#!/bin/bash
# ccpm-settings.sh — CLI accessor for .ccpm/settings.yml.
#
# Usage:
#   bash ccpm-settings.sh <key>     Print one value (boolean → "true"/"false";
#                                    string → trimmed value or empty).
#   bash ccpm-settings.sh --json    Print all settings as a JSON object.
#
# Recognized keys:
#   worktree, ccpm_tracked, method_tracked, github_sync   (boolean)
#   method_dir                                            (string)
#
# Boolean keys default to "false" when absent or malformed. The string key
# defaults to "" (empty) when absent.
#
# IMPORTANT: Caller must cd to the git root before invoking this script.
# Paths are resolved relative to the project root.

set -eu

_settings_file=".ccpm/settings.yml"
_BOOL_KEYS="worktree ccpm_tracked method_tracked github_sync"
_STR_KEYS="method_dir"

# Read the trimmed raw value for a key. Empty if file missing or key absent.
_read_raw() {
  [ -f "$_settings_file" ] || return 0
  grep -E "^$1[[:space:]]*:" "$_settings_file" 2>/dev/null \
    | head -n 1 \
    | sed "s/^$1[[:space:]]*:[[:space:]]*//" \
    | tr -d '[:space:]'
}

_emit_bool() {
  if [ "$(_read_raw "$1")" = "true" ]; then
    echo "true"
  else
    echo "false"
  fi
}

_emit_str() {
  echo "$(_read_raw "$1")"
}

# JSON-escape backslashes and double quotes only — settings values are paths
# or simple identifiers in practice.
_escape_json() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_emit_json() {
  printf '{'
  first=1
  for k in $_BOOL_KEYS; do
    [ $first -eq 0 ] && printf ','
    first=0
    if [ "$(_read_raw "$k")" = "true" ]; then
      printf '"%s":true' "$k"
    else
      printf '"%s":false' "$k"
    fi
  done
  for k in $_STR_KEYS; do
    [ $first -eq 0 ] && printf ','
    first=0
    printf '"%s":"%s"' "$k" "$(_escape_json "$(_read_raw "$k")")"
  done
  printf '}\n'
}

case "${1:-}" in
  --json)
    _emit_json
    ;;
  worktree|ccpm_tracked|method_tracked|github_sync)
    _emit_bool "$1"
    ;;
  method_dir)
    _emit_str "$1"
    ;;
  ""|--help|-h)
    cat >&2 <<EOF
Usage: bash ccpm-settings.sh <key>
       bash ccpm-settings.sh --json

Recognized keys:
  worktree, ccpm_tracked, method_tracked, github_sync   (boolean)
  method_dir                                            (string)
EOF
    exit 1
    ;;
  *)
    echo "ccpm-settings: unknown key '$1'" >&2
    exit 1
    ;;
esac
