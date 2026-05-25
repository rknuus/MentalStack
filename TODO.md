# TODO — deferred follow-up work

These items are intentionally deferred from the initial `uv` migration. They are
**planned future work**, not unfinished business from this project. A future
initiative ("dev tooling setup") should pick them up together.

## ruff — lint + format

Add `ruff` as a dev dependency and a `[tool.ruff]` block to `pyproject.toml`.

```bash
uv add --dev ruff
```

Suggested baseline: line length 100, target `py311`, enable `E`, `F`, `I`, `B`,
`UP`, `SIM`. Run `uv run ruff check .` and `uv run ruff format .` from CI and a
pre-commit hook.

## pytest — test scaffold

Add `pytest` as a dev dependency and create a `tests/` directory at repo root.

```bash
uv add --dev pytest
mkdir tests
```

Seed with one smoke test that imports `mentalstack` and exercises a couple of
the pure helper functions in `server.py` (e.g. `_path`, `_next_open_sibling`,
`render`) against a hand-built state dict. The MCP tool layer and the TUI
`Live` loop need integration-style tests later — keep them out of the initial
scaffold.

## mypy — strict-ish type checking

Add `mypy` as a dev dependency and a `[tool.mypy]` block to `pyproject.toml`.

```bash
uv add --dev mypy
```

Suggested settings: `python_version = "3.11"`, `strict = true`, with per-module
overrides as needed (the MCP `FastMCP` decorators may need some coaxing). Add
type hints to the helper functions in `server.py` and `view.py` first — they
are pure and self-contained — then expand outward.

## Wiring (do once tooling is in)

- A `pre-commit` config that runs `ruff check`, `ruff format --check`, and
  `mypy` on staged files.
- A minimal CI workflow (GitHub Actions): `uv sync`, `uv run ruff check .`,
  `uv run mypy`, `uv run pytest`.
