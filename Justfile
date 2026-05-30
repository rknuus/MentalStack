# MentalStack dev tasks. Run `just` for the list, `just <recipe>` to invoke.

# Default: show available recipes.
default:
    @just --list

# Install runtime and dev dependencies into .venv.
sync:
    uv sync

# Run the test suite.
test:
    uv run pytest

# Lint with ruff.
lint:
    uv run ruff check .

# Auto-format with ruff.
fmt:
    uv run ruff format .

# Check formatting without modifying anything.
fmt-check:
    uv run ruff format --check .

# Type-check src/ with mypy.
typecheck:
    uv run mypy src

# Run every pre-PR gate. CI should run the same thing.
check: lint fmt-check typecheck test

# Run the MCP server (for ad-hoc testing — Claude Code launches it itself).
serve:
    uv run mentalstack-server

# Run the TUI viewer against the current directory's .mentalstack.json.
view:
    uv run mentalstack-view
