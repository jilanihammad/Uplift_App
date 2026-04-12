from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.repositories import ReminderRepository, UserRepository


def test_upsert_and_complete_reminder(db_session):
    user = UserRepository(db_session).create(email="r@example.com")
    repo = ReminderRepository(db_session)

    future = datetime.now(timezone.utc) + timedelta(days=1)
    reminder = repo.upsert_session_reminder(
        user_id=user.id, scheduled_time=future, title="Call back", description="checkin"
    )
    assert reminder.id is not None
    assert reminder.is_completed is False

    new_time = future + timedelta(hours=2)
    same = repo.upsert_session_reminder(user_id=user.id, scheduled_time=new_time)
    assert same.id == reminder.id
    assert same.scheduled_time.replace(tzinfo=timezone.utc) == new_time

    fetched = repo.get_next_session_reminder(user.id)
    assert fetched is not None
    assert fetched.id == reminder.id

    completed = repo.mark_session_reminder_completed(reminder.id)
    assert completed is not None and completed.is_completed is True


def test_no_reminders_returns_none(db_session):
    user = UserRepository(db_session).create(email="empty@example.com")
    repo = ReminderRepository(db_session)
    assert repo.get_next_session_reminder(user.id) is None
