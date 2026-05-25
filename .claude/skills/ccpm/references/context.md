# Context Management

Utilities for creating, updating, and loading project context files in `.ccpm/context/`.

---

## Context Create

**Trigger**: User wants to establish baseline project context, or says "create context", "set up context".

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- Check if `.ccpm/context/` exists and has files. If so, count them and confirm overwrite: "Found {count} existing context files. Overwrite? (yes/no)". If no, suggest "update context" instead.
- Detect project type from root files: `package.json` (Node.js), `requirements.txt`/`pyproject.toml` (Python), `Cargo.toml` (Rust), `go.mod` (Go), `Gemfile` (Ruby), `pom.xml`/`build.gradle` (Java), `composer.json` (PHP), `Package.swift` (Swift), `pubspec.yaml` (Dart), `CMakeLists.txt` (C/C++), `*.sln`/`*.csproj` (.NET).
- Ensure `.ccpm/context/` exists: `mkdir -p .ccpm/context/`
- Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

### Process

Analyze the codebase before writing anything:
- Read `README.md` and any docs directory
- Inspect root directory structure: `ls -la`
- Check git info: `bash "${SKILL_ROOT:-.claude/skills/ccpm}/references/scripts/ccpm-git-info.sh" --full` and `git remote -v`
- Scan source files to understand language mix and project shape
- Read package/build files for dependencies

Generate nine context files in `.ccpm/context/`, each with this frontmatter:

```yaml
---
created: <current datetime>
last_updated: <current datetime>
version: 1.0
author: Claude Code PM System
---
```

**Files to create:**

| File | Purpose |
|------|---------|
| `project-overview.md` | High-level summary: what it does, key features, integration points |
| `project-brief.md` | Core purpose, goals, success criteria |
| `tech-context.md` | Language, framework, dependencies, dev tools, build system |
| `progress.md` | Current state: branch, recent commits, outstanding changes, next steps |
| `project-structure.md` | Directory layout, key files, module organization |
| `system-patterns.md` | Architecture decisions, design patterns, data flow |
| `product-context.md` | Target users, use cases, constraints, domain concepts |
| `project-style-guide.md` | Coding conventions, linting rules, naming patterns |
| `project-vision.md` | Long-term direction, roadmap, strategic goals |

**Quality gates before saving:**
- No placeholder text in any file
- Each file has valid YAML frontmatter with real datetime
- Content is specific to this project, not generic

**After creation**: Confirm with file count and project summary. Suggest "prime context" to load in new sessions, "update context" to refresh later.

---

## Context Update

**Trigger**: User wants to refresh context, or says "update context", "refresh context".

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- Verify `.ccpm/context/` exists and has files. If empty or missing: "No context to update. Run context create first."
- Gather change information: `bash "${SKILL_ROOT:-.claude/skills/ccpm}/references/scripts/ccpm-git-info.sh" --full`
  - Check dependency file diffs if relevant
- Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

### Process

Evaluate each context file for staleness. Update frequency varies by file:

| File | Update when |
|------|-------------|
| `progress.md` | **Always** — recent commits, current branch, next steps |
| `project-structure.md` | New directories/files added or significant reorganization |
| `tech-context.md` | Dependencies added/removed/upgraded |
| `system-patterns.md` | Architecture changed or new patterns adopted |
| `product-context.md` | Requirements or user needs changed |
| `project-style-guide.md` | New conventions or linting rules adopted |
| `project-overview.md` | Major milestones reached or features shipped |
| `project-brief.md` | Rarely — only if fundamental goals changed |
| `project-vision.md` | Rarely — only for strategic direction shifts |

**Update rules:**
1. Read existing file content first
2. Make targeted, surgical edits — do not regenerate unchanged sections
3. Preserve the original `created` field
4. Update `last_updated` to current datetime
5. Increment `version` for significant changes (e.g., 1.0 to 1.1)
6. Do not overwrite user-edited content — merge intelligently
7. Skip files with no relevant changes (preserve accurate timestamps)

**After update**: Report which files were updated, which were skipped (with reason), and any errors. Show timestamp of update.

---

## Context Prime

**Trigger**: User says "prime context", "load context", at the start of a new session.

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- Verify `.ccpm/context/` exists and has files. If missing: "No context found. Run context create first."
- For each file found, validate:
  - File is readable and non-empty
  - Frontmatter starts with `---` and parses as valid YAML
- Note any issues (empty files, missing frontmatter) but continue with what's available.
- Check current git state: `bash "${SKILL_ROOT:-.claude/skills/ccpm}/references/scripts/ccpm-git-info.sh"`

### Process

Load context files in priority order:

**Priority 1 — Essential** (load first):
1. `project-overview.md` — what the project is
2. `project-brief.md` — core purpose and goals
3. `tech-context.md` — technical stack

**Priority 2 — Current state** (load second):
4. `progress.md` — what's happening now
5. `project-structure.md` — how code is organized

**Priority 3 — Deep context** (load third):
6. `system-patterns.md` — architecture and patterns
7. `product-context.md` — users and requirements
8. `project-style-guide.md` — coding conventions
9. `project-vision.md` — long-term direction

**Error recovery for missing critical files:**
- `project-overview.md` missing: fall back to `README.md`
- `tech-context.md` missing: analyze package/build files directly
- `progress.md` missing: check recent git commits

**After loading**: Provide a summary:
- Project name and type
- Current status (from progress.md)
- Current branch
- Files loaded: {success}/{total}
- Any warnings about missing or invalid files
- Brief 2-3 sentence project summary

---

## Context File Frontmatter Schema

All files in `.ccpm/context/` use this frontmatter:

```yaml
---
created: 2024-01-15T14:30:45Z      # Set once at creation, never change
last_updated: 2024-01-15T14:30:45Z  # Update on any modification
version: 1.0                        # Increment on significant changes
author: Claude Code PM System       # Always this value
---
```

**Rules:**
- Always use real datetime from `date -u +"%Y-%m-%dT%H:%M:%SZ"` — never placeholders
- Never modify the `created` field after initial creation
- The `last_updated` field is only changed when file content actually changes

---

## Important Notes

- Context files describe the project for future sessions — write for an agent that knows nothing about this codebase
- Be specific and concrete, not generic. "Uses React 18 with TypeScript" not "Uses a modern frontend framework"
- Keep files focused. Each file has one job — don't duplicate information across files
- When updating, preserve any sections the user has manually edited or annotated
