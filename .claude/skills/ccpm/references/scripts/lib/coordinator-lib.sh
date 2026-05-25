#!/bin/bash
# coordinator-lib.sh — Sourceable helpers for CCPM coordinator scripts.
#
# Source this from a bash coordinator script:
#   source <skill-root>/references/scripts/lib/coordinator-lib.sh
#
# Lives under lib/ to signal that it is internal infrastructure: agents
# never invoke this file directly. The eight ccpm-*.sh coordinator scripts
# (one level up) source it via `$_self_dir/lib/coordinator-lib.sh`.
#
# The library is bash-only — coordinator scripts run via `bash <script>.sh`
# and source this file into that bash subprocess. Caller-shell never matters.
#
# Internally, coord_init invokes ccpm-detect-mode.sh as a subprocess via
# `eval "$(bash …)"`. This $() use is intentional and safe: it executes
# inside the library function (a script body), not in an agent-facing
# Bash tool call. Agents that source coordinator-lib.sh do so via a
# coordinator script, never directly.
#
# Provides:
#   coord_init <initiative>                 Populate flag variables.
#   coord_msg_path <kind> <init> [<epic>] [<task-id>]
#                                            Canonical commit-message-file path.
#   coord_commit <msg-file> <pathspec…>     FR-8 atomic commit recipe.
#   coord_push_branch <branch>              Push gated on ONLINE.
#   coord_status <line>                     Uniform stdout status (text or JSON).
#
# Caller env:
#   COORD_OUTPUT_MODE=json   Switches coord_status to JSON form.
#
# IMPORTANT: Caller must cd to the git project root before sourcing.

# Resolve the parent of this library's directory so it can locate the
# coordinator scripts and ccpm-detect-mode.sh, which live one level up
# at references/scripts/.
_coord_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# coord_init <initiative>
#
# Runs ccpm-detect-mode.sh once and sets the six flag variables in the
# calling script's scope:
#   CCPM_TRACKED, METHOD_DIR, METHOD_TRACKED, WORKTREE_ACTIVE, ONLINE, SYNC_ENABLED
#
# Returns:
#   0  success
#   2  METHOD_DIR multi-match (per FR-1)
#   1  internal error (e.g. detection script not found)
# ---------------------------------------------------------------------------
coord_init() {
  local initiative="${1:-}"
  local detect="$_coord_lib_dir/ccpm-detect-mode.sh"
  if [ ! -f "$detect" ]; then
    echo "coord_init: ccpm-detect-mode.sh not found at $detect" >&2
    return 1
  fi
  # Capture both stdout (KEY=VALUE) and exit code. Stderr passes through
  # so multi-match errors surface to the user verbatim.
  local output rc
  output="$(bash "$detect" "$initiative")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    return "$rc"
  fi
  eval "$output"
}

# ---------------------------------------------------------------------------
# coord_msg_path <kind> <initiative> [<epic>] [<task-id>]
#
# Emits the canonical commit-message-file path per FR-8 to stdout.
#
# kind values:
#   initiative  →  .ccpm/initiatives/<i>/<i>-commit-msg.txt
#   epic        →  .ccpm/initiatives/<i>/<e>/<e>-commit-msg.txt
#   tasks       →  .ccpm/initiatives/<i>/<e>/tasks-commit-msg.txt
#   task        →  .ccpm/initiatives/<i>/<e>/<task-id>-commit-msg.txt
# ---------------------------------------------------------------------------
coord_msg_path() {
  local kind="${1:-}" init="${2:-}" epic="${3:-}" task="${4:-}"
  case "$kind" in
    initiative)
      [ -n "$init" ] || { echo "coord_msg_path: initiative kind requires <init>" >&2; return 1; }
      echo ".ccpm/initiatives/$init/$init-commit-msg.txt"
      ;;
    epic)
      [ -n "$init" ] && [ -n "$epic" ] || { echo "coord_msg_path: epic kind requires <init> <epic>" >&2; return 1; }
      echo ".ccpm/initiatives/$init/$epic/$epic-commit-msg.txt"
      ;;
    tasks)
      [ -n "$init" ] && [ -n "$epic" ] || { echo "coord_msg_path: tasks kind requires <init> <epic>" >&2; return 1; }
      echo ".ccpm/initiatives/$init/$epic/tasks-commit-msg.txt"
      ;;
    task)
      [ -n "$init" ] && [ -n "$epic" ] && [ -n "$task" ] || { echo "coord_msg_path: task kind requires <init> <epic> <task-id>" >&2; return 1; }
      echo ".ccpm/initiatives/$init/$epic/$task-commit-msg.txt"
      ;;
    *)
      echo "coord_msg_path: unknown kind '$kind' (expected: initiative|epic|tasks|task)" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# coord_commit <msg-file> <pathspec…>
#
# FR-8 atomic commit recipe. Runs `git commit -F <msg> -- <pathspecs>` then
# unconditionally removes the message file. Empty-diff is treated as a
# no-op (returns 0 with a status note via coord_status).
#
# Returns:
#   0  commit created OR no changes to commit
#   1  commit failed for another reason
# ---------------------------------------------------------------------------
coord_commit() {
  local msg="${1:-}"
  shift || true
  if [ -z "$msg" ] || [ "$#" -eq 0 ]; then
    echo "coord_commit: usage: coord_commit <msg-file> <pathspec...>" >&2
    return 1
  fi
  if [ ! -f "$msg" ]; then
    echo "coord_commit: message file not found: $msg" >&2
    return 1
  fi

  # First non-empty line of the message file → commit subject (used in status).
  local subject
  subject="$(grep -m 1 -v '^[[:space:]]*$' "$msg" 2>/dev/null || true)"

  # Register intent-to-add for any path that may be a brand-new file. Without
  # this, `git commit -- <new-path>` fails with "did not match any file(s)".
  # Run per-pathspec so a no-match on one (e.g. an empty conditional glob)
  # doesn't taint registration of the others. Already-tracked paths and
  # nonexistent paths are no-ops; the `|| true` swallows that failure mode.
  local _coord_p
  for _coord_p in "$@"; do
    git add -N -- "$_coord_p" 2>/dev/null || true
  done

  local out rc
  out="$(git commit -F "$msg" -- "$@" 2>&1)"
  rc=$?

  rm -f "$msg"

  if [ "$rc" -eq 0 ]; then
    coord_status "committed: $subject"
    return 0
  fi

  # Empty-diff or pathspec-doesn't-match: treat as success with informative note.
  # Coordinators often pass conditional pathspecs derived from mode flags, so a
  # missing path here is "the gating flag was off," not a real error.
  if echo "$out" | grep -qE 'nothing to commit|nothing added to commit|no changes added|did not match any file'; then
    coord_status "no changes to commit (subject: $subject)"
    return 0
  fi

  echo "$out" >&2
  return 1
}

# ---------------------------------------------------------------------------
# coord_push_branch <branch>
#
# Pushes the named branch to origin, gated solely on ONLINE. When
# ONLINE=false (or unset), prints a status note via coord_status and
# returns 0 — pushing is opportunistic, not required for correctness.
#
# Caller is expected to have run coord_init first; ONLINE is read from
# the shell environment.
# ---------------------------------------------------------------------------
coord_push_branch() {
  local branch="${1:-}"
  if [ -z "$branch" ]; then
    echo "coord_push_branch: usage: coord_push_branch <branch>" >&2
    return 1
  fi

  if [ "${ONLINE:-false}" != "true" ]; then
    coord_status "ONLINE=false; skipping push of $branch"
    return 0
  fi

  git push origin "$branch"
}

# ---------------------------------------------------------------------------
# coord_status <line>
#
# Emits a one-line status to stdout. By default plain text; switches to a
# JSON object {"status":"<line>"} when COORD_OUTPUT_MODE=json.
# ---------------------------------------------------------------------------
coord_status() {
  local line="${1:-}"
  case "${COORD_OUTPUT_MODE:-text}" in
    json)
      # Escape backslashes and double quotes for JSON.
      local escaped
      escaped="$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      printf '{"status":"%s"}\n' "$escaped"
      ;;
    *)
      echo "$line"
      ;;
  esac
}
