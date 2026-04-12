"""Typed async event bus + domain events.

Usage::

    from app.core.events import event_bus, SessionStartedEvent

    await event_bus.emit(SessionStartedEvent(user_id=42, session_id="abc"))

For hot-path emissions where awaiting would block the per-chunk loop::

    event_bus.emit_nowait(TTSCompletedEvent(...))
"""
from __future__ import annotations

from .bus import AsyncEventBus, EventHandler, event_bus
from .types import (
    AnchorUpsertedEvent,
    Event,
    MessageReceivedEvent,
    MoodLoggedEvent,
    ProfileUpdatedEvent,
    SessionEndedEvent,
    SessionStartedEvent,
    TTSCompletedEvent,
    VoiceTranscribedEvent,
)

__all__ = [
    "AsyncEventBus",
    "EventHandler",
    "event_bus",
    "Event",
    "AnchorUpsertedEvent",
    "MessageReceivedEvent",
    "MoodLoggedEvent",
    "ProfileUpdatedEvent",
    "SessionEndedEvent",
    "SessionStartedEvent",
    "TTSCompletedEvent",
    "VoiceTranscribedEvent",
]
