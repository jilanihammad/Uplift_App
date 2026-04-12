from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import List, Optional, Sequence, Tuple
from uuid import UUID

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.events import MoodLoggedEvent, event_bus
from app.models.mood_entry import MoodEntry
from app.repositories import MoodEntryRepository

MAX_BATCH_SIZE = 20
LOOKBACK_WINDOW = timedelta(days=60)
FUTURE_WINDOW = timedelta(days=7)
TOKEN_SEPARATOR = "|"


@dataclass
class MoodEntryResult:
    entry: MoodEntry
    created: bool


class MoodEntryValidationError(Exception):
    def __init__(self, message: str, field: Optional[str] = None):
        super().__init__(message)
        self.field = field


def _ensure_utc(dt: datetime, field: str) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _validate_logged_at(logged_at: datetime, now: datetime) -> None:
    if logged_at < now - LOOKBACK_WINDOW:
        raise MoodEntryValidationError(
            "logged_at is older than the 60-day retention window",
            field="logged_at",
        )
    if logged_at > now + FUTURE_WINDOW:
        raise MoodEntryValidationError(
            "logged_at cannot be more than 7 days in the future",
            field="logged_at",
        )


def _truncate_notes(notes: Optional[str]) -> Optional[str]:
    if notes is None:
        return None
    return notes[:512]


def batch_upsert_mood_entries(
    db: Session,
    *,
    user_id: int,
    payloads: Sequence[Tuple[str, int, Optional[str], datetime]],
) -> List[MoodEntryResult]:
    if len(payloads) > MAX_BATCH_SIZE:
        raise MoodEntryValidationError(
            f"Cannot upsert more than {MAX_BATCH_SIZE} entries per request",
            field="entries",
        )

    now = datetime.now(timezone.utc)
    repo = MoodEntryRepository(db)
    results: List[MoodEntryResult] = []

    def _process() -> List[MoodEntryResult]:
        local_results: List[MoodEntryResult] = []
        for client_entry_id, mood, notes, logged_at in payloads:
            normalized_logged_at = _ensure_utc(logged_at, "logged_at")
            _validate_logged_at(normalized_logged_at, now)

            truncated_notes = _truncate_notes(notes)

            entry = repo.get_by_user_and_client_id(user_id, client_entry_id)

            if entry:
                entry.mood = mood
                entry.notes = truncated_notes
                entry.logged_at = normalized_logged_at
                entry.updated_at = now
                created = False
            else:
                entry = MoodEntry(
                    user_id=user_id,
                    client_entry_id=client_entry_id,
                    mood=mood,
                    notes=truncated_notes,
                    logged_at=normalized_logged_at,
                    created_at=now,
                    updated_at=now,
                )
                repo.add(entry)
                created = True

            local_results.append(MoodEntryResult(entry=entry, created=created))
        return local_results

    results = _process()

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        results = _process()
        db.commit()

    for result in results:
        db.refresh(result.entry)

    for result in results:
        event_bus.emit_nowait(
            MoodLoggedEvent(
                user_id=user_id,
                mood_value=result.entry.mood,
                has_notes=bool(result.entry.notes),
                is_new=result.created,
            )
        )

    return results


def _decode_pagination_token(token: str) -> Tuple[datetime, UUID]:
    try:
        decoded = base64.urlsafe_b64decode(token.encode()).decode()
        logged_at_str, entry_id_str = decoded.split(TOKEN_SEPARATOR, 1)
        logged_at = datetime.fromisoformat(logged_at_str)
        if logged_at.tzinfo is None:
            logged_at = logged_at.replace(tzinfo=timezone.utc)
        else:
            logged_at = logged_at.astimezone(timezone.utc)
        entry_id = UUID(entry_id_str)
        return logged_at, entry_id
    except Exception as exc:  # noqa: BLE001
        raise MoodEntryValidationError("Invalid pagination token", field="before") from exc


def _encode_pagination_token(logged_at: datetime, entry_id: UUID) -> str:
    payload = f"{logged_at.isoformat()}|{entry_id}"
    return base64.urlsafe_b64encode(payload.encode()).decode()


def fetch_mood_entries(
    db: Session,
    *,
    user_id: int,
    since: Optional[datetime],
    limit: int,
    before: Optional[str],
) -> Tuple[List[MoodEntry], Optional[str]]:
    now = datetime.now(timezone.utc)
    cutoff = now - LOOKBACK_WINDOW

    normalized_since: Optional[datetime] = None
    if since:
        normalized_since = _ensure_utc(since, "since")
        if normalized_since < cutoff:
            normalized_since = cutoff

    before_logged_at: Optional[datetime] = None
    before_id: Optional[UUID] = None
    if before:
        before_logged_at, before_id = _decode_pagination_token(before)

    entries = MoodEntryRepository(db).list_for_user(
        user_id,
        cutoff=cutoff,
        since=normalized_since,
        before_logged_at=before_logged_at,
        before_id=before_id,
        limit=limit,
    )

    has_more = len(entries) > limit
    if has_more:
        entries = entries[:limit]

    next_before: Optional[str] = None
    if has_more and entries:
        last_entry = entries[-1]
        next_before = _encode_pagination_token(last_entry.logged_at, last_entry.id)

    return entries, next_before
