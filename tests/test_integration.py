"""MCP-protocol integration tests.

Spawns ``mentalstack-server`` as a real subprocess over stdio and exercises
the FastMCP wiring — tool registration, schema generation, protocol-level
argument validation — that the unit tests deliberately bypass.

Client API: uses the ``mcp`` SDK's ``stdio_client`` + ``ClientSession`` pair
(async). ``asyncio_mode = "auto"`` in pyproject.toml lets pytest discover
``async def test_*`` functions without per-test markers.

A ``@asynccontextmanager`` helper handles session setup/teardown inline in
each test. A yielding pytest-asyncio fixture would split the lifecycle
across two tasks and trip anyio's cancel-scope ownership check at
teardown.

State isolation: each test gets its own ``MENTALSTACK_FILE`` via the
``state_file`` fixture; the subprocess inherits that env var so its server
writes to the per-test path.
"""

from __future__ import annotations

import json
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from mcp import ClientSession, StdioServerParameters, stdio_client

EXPECTED_TOOLS = {"add", "complete", "enter", "exit", "goto", "insert", "move", "refine", "view"}


def _server_params(state_file: Path) -> StdioServerParameters:
    """Spawn the server via ``python -m mentalstack.server`` using the test interpreter."""
    return StdioServerParameters(
        command=sys.executable,
        args=["-m", "mentalstack.server"],
        env={"MENTALSTACK_FILE": str(state_file)},
    )


@asynccontextmanager
async def _open_session(state_file: Path) -> AsyncIterator[ClientSession]:
    """Spawn the server and yield an initialised ``ClientSession``."""
    async with (
        stdio_client(_server_params(state_file)) as (read, write),
        ClientSession(read, write) as sess,
    ):
        await sess.initialize()
        yield sess


def _text(content_list: list[Any]) -> str:
    """Extract concatenated text content from a tool response."""
    return "".join(c.text for c in content_list if hasattr(c, "text"))


# --------------------------------------------------------------------------- tool registration


class TestToolRegistration:
    async def test_all_nine_tools_listed(self, state_file: Path) -> None:
        async with _open_session(state_file) as session:
            result = await session.list_tools()
        assert {t.name for t in result.tools} == EXPECTED_TOOLS

    async def test_enter_schema_requires_string_title(self, state_file: Path) -> None:
        async with _open_session(state_file) as session:
            result = await session.list_tools()
        enter = next(t for t in result.tools if t.name == "enter")
        assert "title" in enter.inputSchema.get("required", [])
        assert enter.inputSchema["properties"]["title"]["type"] == "string"

    async def test_insert_where_is_enum(self, state_file: Path) -> None:
        async with _open_session(state_file) as session:
            result = await session.list_tools()
        insert = next(t for t in result.tools if t.name == "insert")
        assert insert.inputSchema["properties"]["where"]["enum"] == ["before", "after"]

    async def test_move_where_is_enum(self, state_file: Path) -> None:
        async with _open_session(state_file) as session:
            result = await session.list_tools()
        move = next(t for t in result.tools if t.name == "move")
        assert move.inputSchema["properties"]["where"]["enum"] == ["before", "after"]


# --------------------------------------------------------------------------- round-trip


class TestRoundTrip:
    async def test_enter_then_view_reflects_change(self, state_file: Path) -> None:
        async with _open_session(state_file) as session:
            await session.call_tool("enter", {"title": "hello"})
            view_result = await session.call_tool("view", {})
        assert "hello" in _text(view_result.content)

    async def test_enter_writes_to_state_file(self, state_file: Path) -> None:
        async with _open_session(state_file) as session:
            await session.call_tool("enter", {"title": "persisted"})
        assert state_file.exists()
        data = json.loads(state_file.read_text(encoding="utf-8"))
        assert data["nodes"]["1"]["title"] == "persisted"


# --------------------------------------------------------------------------- protocol validation


class TestProtocolValidation:
    async def test_bad_where_value_does_not_mutate_state(self, state_file: Path) -> None:
        """``where="sideways"`` violates the Literal enum.

        MCP servers may surface this as a JSON-RPC error raised on the
        client OR as an error-flagged tool result; both count as
        "rejected before the function runs". The load-bearing assertion
        is that the state file is not mutated.
        """
        before = state_file.read_bytes() if state_file.exists() else b""
        async with _open_session(state_file) as session:
            try:
                result = await session.call_tool(
                    "insert", {"title": "x", "anchor": "0", "where": "sideways"}
                )
            except Exception:
                pass  # protocol-level rejection — fine
            else:
                assert getattr(result, "isError", False) is True, (
                    f"server accepted bad where value: {result}"
                )
        after = state_file.read_bytes() if state_file.exists() else b""
        assert after == before, "state file mutated by an invalid call"


# --------------------------------------------------------------------------- guard pass-through


class TestGuardOverProtocol:
    async def test_corrupt_file_surfaces_warning_via_mcp(self, state_file: Path) -> None:
        """End-to-end check: a botched file produces the guard's warning text
        through the real protocol, with the file byte-identical afterwards."""
        state_file.write_text("{garbage", encoding="utf-8")
        before = state_file.read_bytes()
        async with _open_session(state_file) as session:
            result = await session.call_tool("enter", {"title": "hello"})
        out = _text(result.content)
        assert "⚠" in out and "refusing to mutate" in out
        assert state_file.read_bytes() == before, "guard let the file get clobbered"
