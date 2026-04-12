"""Typed async event bus for cross-cutting domain events.

Singleton — ``event_bus = AsyncEventBus()``. Subscribers register at
startup; emitters fire and forget on the hot path or await for ordered
delivery off the hot path.

Hot-path safety:
- ``emit_nowait`` schedules a ``create_task`` and tracks the task in a
  module-level set so the task isn't garbage-collected mid-flight (a
  documented asyncio footgun).
- A soft cap of 1000 in-flight tasks logs a warning and drops new events
  rather than letting them pile up under a stalled handler.

Handler isolation:
- Each handler runs in its own try/except.
- In dev (``settings.ENV == 'development'`` AND ``settings.EVENT_BUS_STRICT``),
  exceptions re-raise after the fanout completes so silent bugs surface
  during local testing. In prod they are logged + counted.
"""
from __future__ import annotations

import asyncio
import logging
from collections import defaultdict
from typing import Any, Awaitable, Callable, DefaultDict, List, Set, Type, TypeVar

from .types import Event

logger = logging.getLogger(__name__)

E = TypeVar("E", bound=Event)
EventHandler = Callable[[Any], Awaitable[None]]

_PENDING_TASK_SOFT_CAP = 1000


class AsyncEventBus:
    def __init__(self) -> None:
        self._subscribers: DefaultDict[Type[Event], List[EventHandler]] = defaultdict(list)
        self._pending: Set[asyncio.Task] = set()
        self._strict_mode = False
        self.handler_error_count = 0
        self.dropped_event_count = 0

    # ------------------------------------------------------------------
    # Configuration
    # ------------------------------------------------------------------

    def set_strict_mode(self, strict: bool) -> None:
        """When True, ``emit`` re-raises after fanout if any handler failed.

        Default False. App startup should set True in development.
        """
        self._strict_mode = strict

    def reset(self) -> None:
        """Clear all subscribers and pending tasks (for tests)."""
        self._subscribers.clear()
        for task in list(self._pending):
            if not task.done():
                task.cancel()
        self._pending.clear()
        self.handler_error_count = 0
        self.dropped_event_count = 0

    # ------------------------------------------------------------------
    # Subscription
    # ------------------------------------------------------------------

    def subscribe(self, event_type: Type[E], handler: Callable[[E], Awaitable[None]]) -> None:
        self._subscribers[event_type].append(handler)  # type: ignore[arg-type]

    def unsubscribe(self, event_type: Type[E], handler: Callable[[E], Awaitable[None]]) -> None:
        if handler in self._subscribers.get(event_type, []):
            self._subscribers[event_type].remove(handler)  # type: ignore[arg-type]

    # ------------------------------------------------------------------
    # Emission
    # ------------------------------------------------------------------

    async def emit(self, event: Event) -> None:
        """Fan event out to all subscribers concurrently and await completion.

        Handlers are isolated — one exception does not abort siblings. In
        strict mode the first exception re-raises after every handler finishes.
        """
        if not isinstance(event, Event):
            raise TypeError(
                f"emit() expected Event subclass, got {type(event).__name__}"
            )

        handlers = list(self._subscribers.get(type(event), ()))
        if not handlers:
            return

        results = await asyncio.gather(
            *(self._run_handler(handler, event) for handler in handlers),
            return_exceptions=True,
        )

        first_error: BaseException | None = None
        for result in results:
            if isinstance(result, BaseException):
                self.handler_error_count += 1
                logger.exception(
                    "event_bus handler error for %s: %s",
                    type(event).__name__,
                    result,
                    exc_info=result,
                )
                if first_error is None:
                    first_error = result

        if self._strict_mode and first_error is not None:
            raise first_error

    def emit_nowait(self, event: Event) -> None:
        """Fire-and-forget emission.

        Used on the per-chunk TTS hot path. Caller never awaits. The task is
        tracked in ``self._pending`` to prevent garbage collection from
        cancelling it mid-flight (asyncio docs flag this as a footgun).
        """
        if not isinstance(event, Event):
            raise TypeError(
                f"emit_nowait() expected Event subclass, got {type(event).__name__}"
            )

        if len(self._pending) >= _PENDING_TASK_SOFT_CAP:
            self.dropped_event_count += 1
            logger.warning(
                "event_bus pending task soft cap reached (%d) — dropping %s",
                _PENDING_TASK_SOFT_CAP,
                type(event).__name__,
            )
            return

        try:
            task = asyncio.create_task(self.emit(event))
        except RuntimeError:
            # No running loop (synchronous test context) — drop quietly
            self.dropped_event_count += 1
            return
        self._pending.add(task)
        task.add_done_callback(self._pending.discard)

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    async def _run_handler(self, handler: EventHandler, event: Event) -> None:
        await handler(event)


# Module-level singleton
event_bus = AsyncEventBus()
