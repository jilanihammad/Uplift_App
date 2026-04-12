"""Session summary repository.

Exposes per-(user, session) lookup. Client-vs-server timestamp upsert
logic stays in session_summary_service.
"""
from __future__ import annotations

from typing import Optional, Protocol
from uuid import UUID

from app.models.session_summary import SessionSummary

from .base import BaseRepository


class ISessionSummaryRepository(Protocol):
    def get_by_user_and_session(
        self, user_id: int, session_id: str
    ) -> Optional[SessionSummary]: ...
    def add(self, entity: SessionSummary) -> SessionSummary: ...


class SessionSummaryRepository(BaseRepository[SessionSummary, UUID]):
    model = SessionSummary

    def get_by_user_and_session(
        self, user_id: int, session_id: str
    ) -> Optional[SessionSummary]:
        return (
            self.db.query(SessionSummary)
            .filter(
                SessionSummary.user_id == user_id,
                SessionSummary.session_id == session_id,
            )
            .one_or_none()
        )
