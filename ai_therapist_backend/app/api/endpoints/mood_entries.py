from __future__ import annotations

import hashlib
import logging
import time
from collections import defaultdict, deque
from datetime import datetime
from threading import Lock
from typing import Deque, Dict, Optional, Tuple

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from sqlalchemy.orm import Session

from app.api.deps.auth import AuthenticatedUser, get_current_user
from app.core.logging_utils import LatencyTimer
from app.core.observability import record_counter, record_latency
from app.db.session import get_db
from app.schemas import (
    MoodEntriesResponse,
    MoodEntryBatchUpsertRequest,
    MoodEntryBatchUpsertResponse,
    MoodEntryOut,
)
from app.services.mood_entry_service import (
    MAX_BATCH_SIZE,
    MoodEntryValidationError,
    batch_upsert_mood_entries,
    fetch_mood_entries,
)

logger = logging.getLogger(__name__)
router = APIRouter()

RATE_LIMIT_PER_MINUTE = 10
RATE_LIMIT_WINDOW_SECONDS = 60
RATE_LIMIT_BODY_MAX_BYTES = 64 * 1024
SERVICE_NAME = "mood_entries"


def _hash_user_id(user_id: int) -> str:
    return hashlib.sha256(str(user_id).encode("utf-8")).hexdigest()[:12]


class PerUserRateLimiter:
    def __init__(self, limit: int, window_seconds: int) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self._events: Dict[int, Deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def consume(self, user_id: int, amount: int) -> Tuple[bool, int, float]:
        now = time.time()
        with self._lock:
            window_start = now - self.window_seconds
            queue = self._events[user_id]
            while queue and queue[0] <= window_start:
                queue.popleft()

            current_usage = len(queue)
            if current_usage + amount > self.limit:
                reset_in = self.window_seconds - (now - queue[0]) if queue else self.window_seconds
                remaining = max(self.limit - current_usage, 0)
                return False, remaining, max(reset_in, 0.0)

            for _ in range(amount):
                queue.append(now)

            remaining = self.limit - len(queue)
            reset_in = self.window_seconds - (now - queue[0]) if queue else self.window_seconds
            return True, max(remaining, 0), max(reset_in, 0.0)


rate_limiter = PerUserRateLimiter(RATE_LIMIT_PER_MINUTE, RATE_LIMIT_WINDOW_SECONDS)


@router.post(":batch_upsert", response_model=MoodEntryBatchUpsertResponse)
async def batch_upsert_mood_entries_endpoint(
    payload: MoodEntryBatchUpsertRequest,
    request: Request,
    response: Response,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MoodEntryBatchUpsertResponse:
    if not payload.entries:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="entries must not be empty")

    if len(payload.entries) > MAX_BATCH_SIZE:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "message": f"Cannot upsert more than {MAX_BATCH_SIZE} entries per request",
                "field": "entries",
            },
        )

    content_length = request.headers.get("content-length")
    if content_length:
        try:
            if int(content_length) > RATE_LIMIT_BODY_MAX_BYTES:
                raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Payload too large")
        except ValueError:
            logger.debug("Invalid content-length header for mood entries request")

    entry_count = len(payload.entries)
    allowed, remaining, reset_in = rate_limiter.consume(current_user.user.id, entry_count)
    response.headers["X-RateLimit-Limit"] = str(RATE_LIMIT_PER_MINUTE)
    response.headers["X-RateLimit-Remaining"] = str(max(remaining, 0))
    response.headers["X-RateLimit-Reset"] = f"{int(reset_in)}"

    user_hash = _hash_user_id(current_user.user.id)

    if not allowed:
        record_counter(SERVICE_NAME, "write_rate_limited", labels={"user": user_hash})
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many mood entries, please slow down")

    timer = LatencyTimer()

    try:
        tuple_payloads = [
            (
                entry.client_entry_id,
                entry.mood,
                entry.notes,
                entry.logged_at,
            )
            for entry in payload.entries
        ]
        results = batch_upsert_mood_entries(
            db,
            user_id=current_user.user.id,
            payloads=tuple_payloads,
        )
    except MoodEntryValidationError as exc:
        record_counter(SERVICE_NAME, "write_4xx", labels={"user": user_hash})
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail={"message": str(exc), "field": exc.field}) from exc
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        record_counter(SERVICE_NAME, "write_5xx", labels={"user": user_hash})
        logger.exception("Failed to upsert mood entries", extra={"user_hash": user_hash})
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to save mood entries") from exc

    duration_ms = timer.elapsed_ms()
    record_latency(SERVICE_NAME, "batch_upsert", duration_ms, labels={"user": user_hash})
    record_counter(SERVICE_NAME, "write_ok", count=len(results), labels={"user": user_hash})

    api_results = [
        MoodEntryOut(
            id=str(result.entry.id),
            client_entry_id=result.entry.client_entry_id,
            mood=result.entry.mood,
            notes=result.entry.notes,
            logged_at=result.entry.logged_at,
            updated_at=result.entry.updated_at,
        )
        for result in results
    ]

    return MoodEntryBatchUpsertResponse(results=api_results)


@router.get("", response_model=MoodEntriesResponse)
async def list_mood_entries(
    since: Optional[str] = Query(None, description="ISO8601 timestamp to start from"),
    before: Optional[str] = Query(None, description="Opaque pagination token"),
    limit: int = Query(50, ge=1, le=50),
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MoodEntriesResponse:
    user_hash = _hash_user_id(current_user.user.id)
    timer = LatencyTimer()

    parsed_since = None
    if since is not None:
        try:
            parsed_since = datetime.fromisoformat(since)
        except ValueError as exc:  # noqa: B904
            record_counter(SERVICE_NAME, "fetch_4xx", labels={"user": user_hash})
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail={"message": "Invalid since parameter", "field": "since"}) from exc

    try:
        entries, next_before = fetch_mood_entries(
            db,
            user_id=current_user.user.id,
            since=parsed_since,
            limit=limit,
            before=before,
        )
    except MoodEntryValidationError as exc:
        record_counter(SERVICE_NAME, "fetch_4xx", labels={"user": user_hash})
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail={"message": str(exc), "field": exc.field}) from exc
    except Exception as exc:  # noqa: BLE001
        record_counter(SERVICE_NAME, "fetch_5xx", labels={"user": user_hash})
        logger.exception("Failed to fetch mood entries", extra={"user_hash": user_hash})
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to fetch mood entries") from exc

    duration_ms = timer.elapsed_ms()
    record_latency(SERVICE_NAME, "list", duration_ms, labels={"user": user_hash})
    record_counter(SERVICE_NAME, "fetch_ok", count=len(entries), labels={"user": user_hash})

    api_results = [
        MoodEntryOut(
            id=str(entry.id),
            client_entry_id=entry.client_entry_id,
            mood=entry.mood,
            notes=entry.notes,
            logged_at=entry.logged_at,
            updated_at=entry.updated_at,
        )
        for entry in entries
    ]

    return MoodEntriesResponse(results=api_results, next_before=next_before)
