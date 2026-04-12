"""Event bus handlers.

Each handler subscribes to one or more domain event types via
``register_handlers(bus)`` and reacts to them — typically by writing a
log line, pushing to a metrics sink, or persisting an audit record.

Adding a new cross-cutting concern = new handler file + register call.
Services do not change.
"""
from __future__ import annotations

from app.core.events.bus import AsyncEventBus

from .logging_handler import register as register_logging


def register_default_handlers(bus: AsyncEventBus) -> None:
    """Wire built-in handlers to the bus. Called once at app startup."""
    register_logging(bus)


__all__ = ["register_default_handlers"]
