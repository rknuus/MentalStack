# TODO — deferred follow-up work

These items are intentionally deferred from the current initiative — **planned
future work**, not unfinished business.

## CI (GitHub Actions)

Add a workflow that runs the four pre-PR commands on push and on pull request:

```bash
uv sync
uv run pytest
uv run ruff check .
uv run ruff format --check .
uv run mypy src
```

Matrix on at least the supported Python versions (currently `3.11`). Cache the
`uv` install and the `.venv` for faster runs.

## pre-commit hooks

Add a `.pre-commit-config.yaml` that runs `ruff check`, `ruff format --check`,
and `mypy` (against `src`) on staged files. Same gates as CI, just earlier in
the loop.

Suggested install: `uv tool install pre-commit` and document
`pre-commit install` as part of the Development section once landed.
