from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.pool import StaticPool
from sqlalchemy.orm import Session as DbSession, sessionmaker

from app.db.base_class import Base
from app.models.mood_entry import MoodEntry
from app.models.user import User
from app.models.session import Session as SessionModel
from app.services.mood_entry_service import (
    MoodEntryValidationError,
    batch_upsert_mood_entries,
    fetch_mood_entries,
)


def _init_db() -> DbSession:
    engine = create_engine(
        "sqlite://",
        future=True,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(bind=engine, future=True)
    from app.db import session as db_session_module
    db_session_module.engine = engine
    db_session_module.SessionLocal = TestingSessionLocal
    Base.metadata.create_all(
        bind=db_session_module.engine,
        tables=[
            User.__table__,
            SessionModel.__table__,
            MoodEntry.__table__,
        ],
    )
    session = TestingSessionLocal()
    user = User(id=1, email="test@example.com", password_hash="hash")
    session.add(user)
    session.commit()
    return session


@pytest.fixture()
def db_session():
    session = _init_db()
    try:
        yield session
    finally:
        session.close()


def test_batch_upsert_creates_and_updates(db_session: DbSession):
    logged_at = datetime.now(timezone.utc) - timedelta(days=1)

    result = batch_upsert_mood_entries(
        db_session,
        user_id=1,
        payloads=[("entry-1", 3, "initial", logged_at)],
    )

    assert len(result) == 1
    entry = result[0].entry
    assert entry.mood == 3
    assert entry.notes == "initial"

    first_updated_at = entry.updated_at

    result = batch_upsert_mood_entries(
        db_session,
        user_id=1,
        payloads=[("entry-1", 5, "updated note", logged_at + timedelta(hours=1))],
    )

    updated_entry = result[0].entry
    assert updated_entry.mood == 5
    assert updated_entry.notes == "updated note"
    assert updated_entry.updated_at > first_updated_at


def test_batch_upsert_rejects_out_of_window(db_session: DbSession):
    old_logged_at = datetime.now(timezone.utc) - timedelta(days=61)

    with pytest.raises(MoodEntryValidationError) as exc:
        batch_upsert_mood_entries(
            db_session,
            user_id=1,
            payloads=[("entry-old", 2, None, old_logged_at)],
        )

    assert "60-day" in str(exc.value)


def test_fetch_mood_entries_pagination(db_session: DbSession):
    base_time = datetime.now(timezone.utc)

    payloads = [
        (f"entry-{i}", i % 6, None, base_time - timedelta(hours=i))
        for i in range(5)
    ]
    batch_upsert_mood_entries(db_session, user_id=1, payloads=payloads)

    first_page, token = fetch_mood_entries(db_session, user_id=1, since=None, limit=2, before=None)
    assert len(first_page) == 2
    assert token is not None

    second_page, next_token = fetch_mood_entries(db_session, user_id=1, since=None, limit=2, before=token)
    assert len(second_page) == 2
    assert next_token is not None
    assert {e.client_entry_id for e in first_page}.isdisjoint({e.client_entry_id for e in second_page})

    third_page, final_token = fetch_mood_entries(db_session, user_id=1, since=None, limit=2, before=next_token)
    assert len(third_page) == 1
    assert final_token is None


def test_fetch_invalid_token_raises(db_session: DbSession):
    with pytest.raises(MoodEntryValidationError):
        fetch_mood_entries(db_session, user_id=1, since=None, limit=10, before="not-a-token")
