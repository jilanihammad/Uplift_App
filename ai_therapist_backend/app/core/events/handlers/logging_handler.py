"""Structured logging handler.

Subscribes to every domain event and emits a single ``logger.info`` line
in a stable shape. Operators see the same kind of text that the inline
``logger.info("user X logged mood Y")`` calls used to produce; the source
moves from being scattered across services to a single place.
"""
from __future__ import annotations

import logging
from typing import Any

from app.core.events.bus import AsyncEventBus
from app.core.events.types import (
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

logger = logging.getLogger("app.events")


def _format_event(event: Event) -> str:
    """Render an event as ``EventName key=value key=value ...`` for log scan."""
    name = type(event).__name__
    pairs = []
    for slot in getattr(event, "__slots__", ()):  # type: ignore[arg-type]
        if slot in {"event_id", "timestamp"}:
            continue
        value = getattr(event, slot, None)
        if value is None:
            continue
        pairs.append(f"{slot}={value}")
    return f"{name} " + " ".join(pairs) if pairs else name


async def _log_session_started(event: SessionStartedEvent) -> None:
    logger.info(_format_event(event))


async def _log_session_ended(event: SessionEndedEvent) -> None:
    logger.info(_format_event(event))


async def _log_message_received(event: MessageReceivedEvent) -> None:
    logger.info(_format_event(event))


async def _log_tts_completed(event: TTSCompletedEvent) -> None:
    logger.info(_format_event(event))


async def _log_voice_transcribed(event: VoiceTranscribedEvent) -> None:
    logger.info(_format_event(event))


async def _log_mood_logged(event: MoodLoggedEvent) -> None:
    logger.info(_format_event(event))


async def _log_anchor_upserted(event: AnchorUpsertedEvent) -> None:
    logger.info(_format_event(event))


async def _log_profile_updated(event: ProfileUpdatedEvent) -> None:
    logger.info(_format_event(event))


def register(bus: AsyncEventBus) -> None:
    bus.subscribe(SessionStartedEvent, _log_session_started)
    bus.subscribe(SessionEndedEvent, _log_session_ended)
    bus.subscribe(MessageReceivedEvent, _log_message_received)
    bus.subscribe(TTSCompletedEvent, _log_tts_completed)
    bus.subscribe(VoiceTranscribedEvent, _log_voice_transcribed)
    bus.subscribe(MoodLoggedEvent, _log_mood_logged)
    bus.subscribe(AnchorUpsertedEvent, _log_anchor_upserted)
    bus.subscribe(ProfileUpdatedEvent, _log_profile_updated)
