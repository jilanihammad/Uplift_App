"""Smoke tests for the typed AsyncEventBus."""
from __future__ import annotations

import asyncio
from dataclasses import FrozenInstanceError

import pytest

from app.core.events import (
    AsyncEventBus,
    Event,
    MoodLoggedEvent,
    SessionStartedEvent,
)


@pytest.fixture()
def bus() -> AsyncEventBus:
    b = AsyncEventBus()
    yield b
    b.reset()


def test_subscribe_and_emit_roundtrip(bus):
    received: list = []

    async def handler(ev: SessionStartedEvent) -> None:
        received.append(ev)

    bus.subscribe(SessionStartedEvent, handler)

    asyncio.run(bus.emit(SessionStartedEvent(user_id=1, session_id="s1")))

    assert len(received) == 1
    assert received[0].user_id == 1
    assert received[0].session_id == "s1"


def test_multiple_handlers_run_concurrently(bus):
    received: list = []

    async def slow_handler(ev: MoodLoggedEvent) -> None:
        await asyncio.sleep(0.05)
        received.append(("slow", ev.mood_value))

    async def fast_handler(ev: MoodLoggedEvent) -> None:
        received.append(("fast", ev.mood_value))

    bus.subscribe(MoodLoggedEvent, slow_handler)
    bus.subscribe(MoodLoggedEvent, fast_handler)

    async def run():
        start = asyncio.get_event_loop().time()
        await bus.emit(MoodLoggedEvent(user_id=1, mood_value=4))
        return asyncio.get_event_loop().time() - start

    elapsed = asyncio.run(run())
    # Concurrent: should be ~50ms, not 100ms
    assert elapsed < 0.09
    assert len(received) == 2


def test_handler_exception_does_not_kill_siblings(bus):
    received: list = []

    async def failing(ev: SessionStartedEvent) -> None:
        raise ValueError("boom")

    async def succeeding(ev: SessionStartedEvent) -> None:
        received.append(ev)

    bus.subscribe(SessionStartedEvent, failing)
    bus.subscribe(SessionStartedEvent, succeeding)

    asyncio.run(bus.emit(SessionStartedEvent(user_id=1, session_id="s1")))

    assert len(received) == 1
    assert bus.handler_error_count == 1


def test_strict_mode_reraises(bus):
    bus.set_strict_mode(True)

    async def failing(ev: SessionStartedEvent) -> None:
        raise ValueError("strict!")

    bus.subscribe(SessionStartedEvent, failing)

    with pytest.raises(ValueError, match="strict!"):
        asyncio.run(bus.emit(SessionStartedEvent(user_id=1, session_id="s1")))


def test_unsubscribe_removes_handler(bus):
    received: list = []

    async def handler(ev: SessionStartedEvent) -> None:
        received.append(ev)

    bus.subscribe(SessionStartedEvent, handler)
    bus.unsubscribe(SessionStartedEvent, handler)
    asyncio.run(bus.emit(SessionStartedEvent(user_id=1, session_id="s1")))

    assert received == []


def test_events_are_frozen():
    ev = SessionStartedEvent(user_id=1, session_id="s1")
    with pytest.raises(FrozenInstanceError):
        ev.user_id = 99  # type: ignore[misc]


def test_emit_rejects_non_event(bus):
    async def run():
        with pytest.raises(TypeError):
            await bus.emit("not an event")  # type: ignore[arg-type]

    asyncio.run(run())


def test_emit_nowait_returns_immediately(bus):
    received: list = []

    async def slow_handler(ev: SessionStartedEvent) -> None:
        await asyncio.sleep(0.05)
        received.append(ev)

    bus.subscribe(SessionStartedEvent, slow_handler)

    async def run():
        bus.emit_nowait(SessionStartedEvent(user_id=1, session_id="s1"))
        # The emit_nowait call returned without awaiting the handler
        assert received == []
        # But after a brief wait the handler runs
        await asyncio.sleep(0.1)
        assert len(received) == 1

    asyncio.run(run())


def test_emit_to_unknown_event_type_is_noop(bus):
    asyncio.run(bus.emit(Event()))
