"""Reminder repository — migrated from app/crud/reminder.py."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional, Protocol

from sqlalchemy.orm import Session as DBSession

from app.models.reminder import Reminder

SESSION_REMINDER_TITLE = "Therapy Session Reminder"


def _ensure_timezone(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


class IReminderRepository(Protocol):
    def get_next_session_reminder(self, user_id: int) -> Optional[Reminder]: ...
    def upsert_session_reminder(
        self,
        *,
        user_id: int,
        scheduled_time: datetime,
        title: Optional[str] = None,
        description: Optional[str] = None,
    ) -> Reminder: ...
    def mark_session_reminder_completed(self, reminder_id: int) -> Optional[Reminder]: ...


class ReminderRepository:
    def __init__(self, db: DBSession) -> None:
        self.db = db

    def get_next_session_reminder(self, user_id: int) -> Optional[Reminder]:
        now = datetime.now(timezone.utc)
        reminder = (
            self.db.query(Reminder)
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
        return (
            self.db.query(Reminder)
            .filter(
                Reminder.user_id == user_id,
                Reminder.action_plan_id.is_(None),
            )
            .order_by(Reminder.scheduled_time.desc())
            .first()
        )

    def upsert_session_reminder(
        self,
        *,
        user_id: int,
        scheduled_time: datetime,
        title: Optional[str] = None,
        description: Optional[str] = None,
    ) -> Reminder:
        scheduled_time = _ensure_timezone(scheduled_time)
        reminder = (
            self.db.query(Reminder)
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
            self.db.add(reminder)
        self.db.commit()
        self.db.refresh(reminder)
        return reminder

    def mark_session_reminder_completed(self, reminder_id: int) -> Optional[Reminder]:
        reminder = self.db.query(Reminder).filter(Reminder.id == reminder_id).first()
        if not reminder:
            return None
        reminder.is_completed = True
        self.db.commit()
        self.db.refresh(reminder)
        return reminder
