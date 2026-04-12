"""Domain event types for the typed event bus.

Events are FACTS — past tense, immutable. ``frozen=True, slots=True``
prevents handlers from mutating an event mid-fanout, which would silently
poison later handlers.

correlation_id is a per-event field (not a ContextVar). Callers thread it
explicitly from the FastAPI request context. ContextVar plumbing is
deferred until a second consumer needs it.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _new_event_id() -> str:
    return uuid4().hex


@dataclass(frozen=True, slots=True)
class Event:
    """Base class for all domain events."""

    event_id: str = field(default_factory=_new_event_id)
    timestamp: datetime = field(default_factory=_utcnow)
    correlation_id: Optional[str] = None


# ---------------------------------------------------------------------------
# Session lifecycle
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class SessionStartedEvent(Event):
    user_id: int = 0
    session_id: str = ""


@dataclass(frozen=True, slots=True)
class SessionEndedEvent(Event):
    user_id: int = 0
    session_id: str = ""
    duration_ms: float = 0.0


# ---------------------------------------------------------------------------
# Message lifecycle
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class MessageReceivedEvent(Event):
    user_id: int = 0
    session_id: str = ""
    message_id: str = ""
    content_length: int = 0
    is_user_message: bool = True


# ---------------------------------------------------------------------------
# TTS / voice
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class TTSCompletedEvent(Event):
    user_id: Optional[int] = None
    session_id: Optional[str] = None
    text_length: int = 0
    duration_ms: float = 0.0
    provider: str = ""


@dataclass(frozen=True, slots=True)
class VoiceTranscribedEvent(Event):
    user_id: Optional[int] = None
    session_id: Optional[str] = None
    audio_ms: float = 0.0
    text_length: int = 0


# ---------------------------------------------------------------------------
# Mood / anchor / profile (domain writes)
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class MoodLoggedEvent(Event):
    user_id: int = 0
    mood_value: int = 0
    has_notes: bool = False
    is_new: bool = True


@dataclass(frozen=True, slots=True)
class AnchorUpsertedEvent(Event):
    user_id: int = 0
    client_anchor_id: str = ""
    anchor_type: Optional[str] = None
    changed: bool = False


@dataclass(frozen=True, slots=True)
class ProfileUpdatedEvent(Event):
    user_id: int = 0
    version: int = 0
