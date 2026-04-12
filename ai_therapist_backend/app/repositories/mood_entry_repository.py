"""Mood entry repository.

Exposes typed query methods used by mood_entry_service. Repo never commits;
the service owns the unit-of-work (including the IntegrityError retry loop
and batch atomicity for client_entry_id idempotency).
"""
from __future__ import annotations

from datetime import datetime
from typing import List, Optional, Protocol
from uuid import UUID

from sqlalchemy import and_, or_

from app.models.mood_entry import MoodEntry

from .base import BaseRepository


class IMoodEntryRepository(Protocol):
    def get_by_user_and_client_id(
        self, user_id: int, client_entry_id: str
    ) -> Optional[MoodEntry]: ...
    def list_for_user(
        self,
        user_id: int,
        *,
        cutoff: datetime,
        since: Optional[datetime] = None,
        before_logged_at: Optional[datetime] = None,
        before_id: Optional[UUID] = None,
        limit: int,
    ) -> List[MoodEntry]: ...
    def add(self, entity: MoodEntry) -> MoodEntry: ...


class MoodEntryRepository(BaseRepository[MoodEntry, UUID]):
    model = MoodEntry

    def get_by_user_and_client_id(
        self, user_id: int, client_entry_id: str
    ) -> Optional[MoodEntry]:
        return (
            self.db.query(MoodEntry)
            .filter(
                MoodEntry.user_id == user_id,
                MoodEntry.client_entry_id == client_entry_id,
            )
            .one_or_none()
        )

    def list_for_user(
        self,
        user_id: int,
        *,
        cutoff: datetime,
        since: Optional[datetime] = None,
        before_logged_at: Optional[datetime] = None,
        before_id: Optional[UUID] = None,
        limit: int,
    ) -> List[MoodEntry]:
        """Return entries newest-first with ``(logged_at DESC, id DESC)`` order.

        Pagination cursor is supplied as decoded ``(before_logged_at, before_id)``;
        the service owns token encode/decode. Returns up to ``limit + 1`` rows so
        the caller can detect ``has_more``.
        """
        query = self.db.query(MoodEntry).filter(
            MoodEntry.user_id == user_id, MoodEntry.logged_at >= cutoff
        )
        if since is not None:
            query = query.filter(MoodEntry.logged_at >= since)
        if before_logged_at is not None and before_id is not None:
            query = query.filter(
                or_(
                    MoodEntry.logged_at < before_logged_at,
                    and_(
                        MoodEntry.logged_at == before_logged_at,
                        MoodEntry.id < before_id,
                    ),
                )
            )
        return (
            query.order_by(MoodEntry.logged_at.desc(), MoodEntry.id.desc())
            .limit(limit + 1)
            .all()
        )
