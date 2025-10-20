from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional, Tuple

from sqlalchemy.orm import Session

from app.models.session_summary import SessionSummary


def _ensure_datetime(value: Optional[datetime]) -> Optional[datetime]:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def upsert_session_summary(
    db: Session,
    *,
    user_id: int,
    session_id: str,
    summary_json: dict,
    client_updated_at: Optional[datetime],
) -> Tuple[SessionSummary, bool]:
    summary = (
        db.query(SessionSummary)
        .filter(SessionSummary.user_id == user_id, SessionSummary.session_id == session_id)
        .one_or_none()
    )

    client_updated_at = _ensure_datetime(client_updated_at)

    if summary:
        if summary.updated_at and client_updated_at and client_updated_at <= summary.updated_at:
            return summary, False

        summary.summary_json = summary_json
        summary.updated_at = _utcnow()
        db.add(summary)
        db.commit()
        db.refresh(summary)
        return summary, True

    summary = SessionSummary(
        user_id=user_id,
        session_id=session_id,
        summary_json=summary_json,
        updated_at=_utcnow(),
    )
    db.add(summary)
    db.commit()
    db.refresh(summary)
    return summary, True
