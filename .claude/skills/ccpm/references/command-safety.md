# Command Safety — Recommended CLAUDE.md Additions

CCPM's conventions enforce command safety rules for CCPM-specific operations. This document covers recommendations for commands *outside* CCPM's scope — language-specific tools, general shell operations, and patterns Claude uses independently.

---

## Why This Matters

Claude Code's permission monitor flags Bash commands that contain shell metacharacters: `&&`, `;`, `2>&1`, `2>/dev/null`, `$()`, backticks, and `#` inside quoted arguments. Flagged commands require individual approval — the user must confirm each one.

Simple commands like `go test ./...` or `npm test` match project-level permission patterns (e.g., `Bash(go test:*)`). Once the user approves the pattern, all matching commands pass automatically. Complex commands like `cd dir && go test 2>&1 | head` don't match any pattern and require approval every time.

The goal: instruct Claude to prefer simple commands so that a small set of project-level permission patterns covers most operations.

---

## Recommended Global ~/.claude/CLAUDE.md Additions

Add these rules to `~/.claude/CLAUDE.md` so they apply across all projects:

```markdown
## Shell Command Style

### Prefer native tools over Bash equivalents
- File reads: Use the Read tool, not `cat`, `head`, or `tail` in Bash
- Content search: Use the Grep tool, not `grep` or `rg` in Bash
- File search: Use the Glob tool, not `find` or `ls` in Bash
- File edits: Use the Edit tool, not `sed` or `awk` in Bash

### One command per Bash call
- Don't: `cd dir && command && cd ..`
- Do: Run each command as a separate Bash tool call

### No stderr redirection
- Don't: `command 2>/dev/null` or `command 2>&1`
- Do: Run the command and handle errors in the next step

### No command substitution in Bash calls
- Don't: `FILES=$(find . -name "*.go")` or complex `$(...)` expressions
- Do: Run the command directly, then reference output in the next step

### No inline scripts
- Don't: `python3 -c "import json; ..."` or `ruby -e "..."`
- Do: Create a script file if parsing is needed, or use native tools

### No `cd <project> && <git|bash> …` wrappers
- Don't: `cd /path/to/project && bash .claude/skills/ccpm/references/scripts/ccpm-detect-mode.sh <init>`
- Don't: `cd /path/to/project && git status`
- Do: Ensure cwd is at the project root first (CCPM recipes assume this — see the "cwd contract" note in `conventions.md` Mode-Detection Preflight), then run `bash .claude/skills/ccpm/references/scripts/ccpm-detect-mode.sh <init>` plain. For the rare case where cwd genuinely cannot be at the project root, use `git -C <project-root> …` (no `cd` wrapper) instead of `cd <project> && git …`.

  *Why*: Claude Code's risky-command monitor flags compound commands that combine `cd` with `git` (or other state-changing operations) as risky and asks the user to approve every such call individually. CCPM phase recipes already perform a "Root check" Preflight step that brings cwd to the project root before any `bash …`/`git …` line runs, so wrapping recipe calls in `cd && …` is both unnecessary and creates per-call approval friction.
```

> **Note**: The fenced block above is the literal text to paste into CLAUDE.md.

---

## Recommended Per-Project CLAUDE.md Additions

Each project should document its common commands so Claude picks simple, recognizable patterns instead of inventing complex alternatives. Add a section like this to the project's `.claude/CLAUDE.md`:

```markdown
## Project Commands

These are the standard commands for this project. Prefer these exact forms:

- Build: `<build command>`
- Test: `<test command>`
- Lint: `<lint command>`
- Format: `<format command>`
```

### Examples by language

**Go:**
```markdown
- Build: `go build ./...`
- Test: `go test ./...`
- Lint: `golangci-lint run`
- Vet: `go vet ./...`
```

**Node.js / TypeScript:**
```markdown
- Install: `npm install`
- Test: `npm test`
- Lint: `npm run lint`
- Build: `npm run build`
```

**Python:**
```markdown
- Test: `pytest`
- Lint: `ruff check .`
- Type check: `mypy .`
- Format: `ruff format .`
```

**Rust:**
```markdown
- Build: `cargo build`
- Test: `cargo test`
- Lint: `cargo clippy`
- Format: `cargo fmt --check`
```

These are illustrative — adapt to your project's actual tooling.

---

## What CCPM Handles Internally

CCPM's `references/conventions.md` already enforces command safety rules for all CCPM-specific operations (status checks, epic management, initiative merges, task creation). You do not need to duplicate those rules in your CLAUDE.md.

The recommendations above cover the gap: commands Claude uses *outside* CCPM's direct control during task execution.
