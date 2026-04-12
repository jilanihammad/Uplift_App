"""Session anchor repository.

Exposes typed query methods. Tombstone (``is_deleted``) handling and
optimistic concurrency stay in anchor_service.
"""
from __future__ import annotations

from datetime import datetime
from typing import List, Optional, Protocol
from uuid import UUID

from app.models.session_anchor import SessionAnchor

from .base import BaseRepository


class ISessionAnchorRepository(Protocol):
    def get_by_user_and_client_id(
        self, user_id: int, client_anchor_id: str
    ) -> Optional[SessionAnchor]: ...
    def list_for_user_since(
        self, user_id: int, *, since: Optional[datetime] = None, limit: int = 100
    ) -> List[SessionAnchor]: ...
    def add(self, entity: SessionAnchor) -> SessionAnchor: ...


class SessionAnchorRepository(BaseRepository[SessionAnchor, UUID]):
    model = SessionAnchor

    def get_by_user_and_client_id(
        self, user_id: int, client_anchor_id: str
    ) -> Optional[SessionAnchor]:
        return (
            self.db.query(SessionAnchor)
            .filter(
                SessionAnchor.user_id == user_id,
                SessionAnchor.client_anchor_id == client_anchor_id,
            )
            .one_or_none()
        )

    def list_for_user_since(
        self,
        user_id: int,
        *,
        since: Optional[datetime] = None,
        limit: int = 100,
    ) -> List[SessionAnchor]:
        """Return anchors ordered by ``updated_at ASC``.

        Includes tombstoned (``is_deleted=True``) rows so that sync clients
        can mirror deletions — service decides whether to filter them out.
        """
        query = self.db.query(SessionAnchor).filter(SessionAnchor.user_id == user_id)
        if since is not None:
            query = query.filter(SessionAnchor.updated_at > since)
        return query.order_by(SessionAnchor.updated_at.asc()).limit(limit).all()
