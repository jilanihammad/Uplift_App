from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable, Optional, Tuple

from sqlalchemy.orm import Session

from app.models.session_anchor import SessionAnchor


def _ensure_datetime(value: Optional[datetime]) -> Optional[datetime]:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def upsert_anchor(
    db: Session,
    *,
    user_id: int,
    client_anchor_id: str,
    anchor_text: str,
    anchor_type: Optional[str],
    confidence: Optional[float],
    last_seen_session_index: Optional[int],
    client_updated_at: Optional[datetime],
) -> Tuple[SessionAnchor, bool]:
    """Upsert anchor. Returns (anchor, changed?)."""
    anchor = (
        db.query(SessionAnchor)
        .filter(SessionAnchor.user_id == user_id, SessionAnchor.client_anchor_id == client_anchor_id)
        .one_or_none()
    )

    client_updated_at = _ensure_datetime(client_updated_at)

    if anchor:
        if anchor.updated_at and client_updated_at and client_updated_at <= anchor.updated_at:
            # Ignore stale update
            return anchor, False

        anchor.anchor_text = anchor_text
        anchor.anchor_type = anchor_type
        anchor.confidence = confidence
        anchor.last_seen_session_index = last_seen_session_index
        anchor.is_deleted = False
        anchor.updated_at = _utcnow()
        db.add(anchor)
        db.commit()
        db.refresh(anchor)
        return anchor, True

    anchor = SessionAnchor(
        user_id=user_id,
        client_anchor_id=client_anchor_id,
        anchor_text=anchor_text,
        anchor_type=anchor_type,
        confidence=confidence,
        last_seen_session_index=last_seen_session_index,
        updated_at=_utcnow(),
    )
    db.add(anchor)
    db.commit()
    db.refresh(anchor)
    return anchor, True


def delete_anchor(
    db: Session,
    *,
    user_id: int,
    client_anchor_id: str,
    client_updated_at: Optional[datetime],
) -> Tuple[SessionAnchor, bool]:
    anchor = (
        db.query(SessionAnchor)
        .filter(SessionAnchor.user_id == user_id, SessionAnchor.client_anchor_id == client_anchor_id)
        .one_or_none()
    )

    client_updated_at = _ensure_datetime(client_updated_at)

    if anchor is None:
        anchor = SessionAnchor(
            user_id=user_id,
            client_anchor_id=client_anchor_id,
            anchor_text="",
            anchor_type=None,
            confidence=None,
            is_deleted=True,
            updated_at=_utcnow(),
        )
        db.add(anchor)
        db.commit()
        db.refresh(anchor)
        return anchor, True

    if anchor.updated_at and client_updated_at and client_updated_at <= anchor.updated_at:
        return anchor, False

    anchor.is_deleted = True
    anchor.updated_at = _utcnow()
    db.add(anchor)
    db.commit()
    db.refresh(anchor)
    return anchor, True


def list_anchors_since(
    db: Session,
    *,
    user_id: int,
    since: Optional[datetime],
    limit: int = 100,
) -> Iterable[SessionAnchor]:
    query = db.query(SessionAnchor).filter(SessionAnchor.user_id == user_id)

    if since is not None:
        since = _ensure_datetime(since)
        query = query.filter(SessionAnchor.updated_at > since)

    return (
        query.order_by(SessionAnchor.updated_at.asc())
        .limit(limit)
        .all()
    )
