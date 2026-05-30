"""Shared pytest fixtures for the mentalstack test suite."""

from __future__ import annotations

import importlib
from collections.abc import Callable
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest


@pytest.fixture
def state_file(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """A tmp ``.mentalstack.json`` path with ``MENTALSTACK_FILE`` pointing at it.

    Use this when the test wants to seed disk state directly or assert on the
    on-disk bytes; combine with the ``server`` fixture when the test exercises
    a tool that needs the module to honour the env var.
    """
    p = tmp_path / ".mentalstack.json"
    monkeypatch.setenv("MENTALSTACK_FILE", str(p))
    return p


@pytest.fixture
def server(state_file: Path) -> ModuleType:
    """A freshly-reloaded ``mentalstack.server`` whose ``STATE_PATH`` matches ``state_file``.

    The module reads ``MENTALSTACK_FILE`` at import time, so each test gets its
    own copy via ``importlib.reload`` after the env var is in place.
    """
    import mentalstack.server as srv

    importlib.reload(srv)
    return srv


@pytest.fixture
def view(state_file: Path) -> ModuleType:
    """A freshly-reloaded ``mentalstack.view`` whose ``STATE_PATH`` matches ``state_file``.

    Same shape as the ``server`` fixture but for the viewer module.
    """
    import mentalstack.view as v

    importlib.reload(v)
    return v


@pytest.fixture
def fresh_state() -> Callable[[], dict[str, Any]]:
    """Factory returning a fresh empty-state dict matching ``_new_state()``."""

    def factory() -> dict[str, Any]:
        return {
            "seq": 1,
            "root": "0",
            "cursor": "0",
            "nodes": {
                "0": {
                    "title": "(top level)",
                    "status": "open",
                    "parent": None,
                    "children": [],
                    "notes": [],
                },
            },
        }

    return factory


@pytest.fixture
def populated_state() -> Callable[[], dict[str, Any]]:
    """Factory returning a small populated tree::

        0 (root, open)
        └── 1 'parent' (open, cursor)
            ├── 2 'a' (open)
            ├── 3 'b' (open)
            └── 4 'c' (done)

    Tests that need a tree shape they can reason about ask for this; tests that
    need a different shape build it inline.
    """

    def factory() -> dict[str, Any]:
        return {
            "seq": 5,
            "root": "0",
            "cursor": "1",
            "nodes": {
                "0": {
                    "title": "(top level)",
                    "status": "open",
                    "parent": None,
                    "children": ["1"],
                    "notes": [],
                },
                "1": {
                    "title": "parent",
                    "status": "open",
                    "parent": "0",
                    "children": ["2", "3", "4"],
                    "notes": [],
                },
                "2": {
                    "title": "a",
                    "status": "open",
                    "parent": "1",
                    "children": [],
                    "notes": [],
                },
                "3": {
                    "title": "b",
                    "status": "open",
                    "parent": "1",
                    "children": [],
                    "notes": [],
                },
                "4": {
                    "title": "c",
                    "status": "done",
                    "parent": "1",
                    "children": [],
                    "notes": [],
                },
            },
        }

    return factory
