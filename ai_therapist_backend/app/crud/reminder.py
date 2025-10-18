"""CRUD operations for reminders, focused on session scheduling."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session as DBSession

from app.models.reminder import Reminder


SESSION_REMINDER_TITLE = "Therapy Session Reminder"


def _ensure_timezone(dt: datetime) -> datetime:
    """Ensure datetime is timezone-aware (UTC)."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def get_next_session_reminder(db: DBSession, user_id: int) -> Optional[Reminder]:
    """Return the next upcoming session reminder for a user."""
    now = datetime.now(timezone.utc)

    reminder = (
        db.query(Reminder)
        .filter(
            Reminder.user_id == user_id,
            Reminder.action_plan_id.is_(None),
            Reminder.scheduled_time >= now,
        )
        .order_by(Reminder.scheduled_time.asc())
        .first()
    )

    if reminder:
        return reminder

    # Fall back to the most recent reminder if no future reminders exist
    return (
        db.query(Reminder)
        .filter(
            Reminder.user_id == user_id,
            Reminder.action_plan_id.is_(None),
        )
        .order_by(Reminder.scheduled_time.desc())
        .first()
    )


def upsert_session_reminder(
    db: DBSession,
    *,
    user_id: int,
    scheduled_time: datetime,
    title: Optional[str] = None,
    description: Optional[str] = None,
) -> Reminder:
    """Create or update the general session reminder for a user."""
    scheduled_time = _ensure_timezone(scheduled_time)

    reminder = (
        db.query(Reminder)
        .filter(
            Reminder.user_id == user_id,
            Reminder.action_plan_id.is_(None),
        )
        .order_by(Reminder.id.desc())
        .first()
    )

    if reminder:
        reminder.scheduled_time = scheduled_time
        reminder.title = title or reminder.title or SESSION_REMINDER_TITLE
        reminder.description = description
        reminder.is_completed = False
    else:
        reminder = Reminder(
            user_id=user_id,
            title=title or SESSION_REMINDER_TITLE,
            description=description,
            scheduled_time=scheduled_time,
            is_completed=False,
        )
        db.add(reminder)

    db.commit()
    db.refresh(reminder)
    return reminder


def mark_session_reminder_completed(db: DBSession, reminder_id: int) -> Optional[Reminder]:
    """Mark a reminder as completed."""
    reminder = db.query(Reminder).filter(Reminder.id == reminder_id).first()
    if not reminder:
        return None

    reminder.is_completed = True
    db.commit()
    db.refresh(reminder)
    return reminder
