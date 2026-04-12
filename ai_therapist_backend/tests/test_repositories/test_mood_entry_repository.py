from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.models.mood_entry import MoodEntry
from app.repositories import MoodEntryRepository, UserRepository


def test_get_by_user_and_client_id_returns_match(db_session):
    user = UserRepository(db_session).create(email="m@example.com")
    repo = MoodEntryRepository(db_session)

    entry = MoodEntry(
        user_id=user.id,
        client_entry_id="cli-1",
        mood=4,
        logged_at=datetime.now(timezone.utc),
    )
    repo.add(entry)
    db_session.commit()  # service owns UoW; tests act as the service here

    found = repo.get_by_user_and_client_id(user.id, "cli-1")
    assert found is entry

    other_user_match = repo.get_by_user_and_client_id(user.id + 9999, "cli-1")
    assert other_user_match is None

    missing = repo.get_by_user_and_client_id(user.id, "nope")
    assert missing is None


def test_list_for_user_orders_and_paginates(db_session):
    user = UserRepository(db_session).create(email="ml@example.com")
    repo = MoodEntryRepository(db_session)

    base = datetime(2026, 1, 1, tzinfo=timezone.utc)
    for i in range(5):
        repo.add(
            MoodEntry(
                user_id=user.id,
                client_entry_id=f"c-{i}",
                mood=i + 1,
                logged_at=base + timedelta(hours=i),
            )
        )
    db_session.commit()

    cutoff = base - timedelta(days=1)
    page = repo.list_for_user(user.id, cutoff=cutoff, limit=3)
    # Repo returns limit+1 to support has_more detection
    assert len(page) == 4
    # Newest first
    assert page[0].mood == 5
    assert page[1].mood == 4

    # Cursor: ask for entries strictly older than the third-newest
    cursor_logged_at = page[2].logged_at
    cursor_id = page[2].id
    next_page = repo.list_for_user(
        user.id,
        cutoff=cutoff,
        before_logged_at=cursor_logged_at,
        before_id=cursor_id,
        limit=10,
    )
    assert all(e.logged_at < cursor_logged_at for e in next_page)
