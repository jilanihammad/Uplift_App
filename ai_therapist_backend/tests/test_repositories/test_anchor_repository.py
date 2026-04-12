from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.models.session_anchor import SessionAnchor
from app.repositories import SessionAnchorRepository, UserRepository


def test_get_and_list_anchors(db_session):
    user = UserRepository(db_session).create(email="a@example.com")
    repo = SessionAnchorRepository(db_session)

    base = datetime(2026, 1, 1, tzinfo=timezone.utc)
    a1 = SessionAnchor(
        user_id=user.id,
        client_anchor_id="anchor-1",
        anchor_text="trust",
        updated_at=base,
    )
    a2 = SessionAnchor(
        user_id=user.id,
        client_anchor_id="anchor-2",
        anchor_text="goal",
        updated_at=base + timedelta(minutes=10),
    )
    repo.add(a1)
    repo.add(a2)
    db_session.commit()

    assert repo.get_by_user_and_client_id(user.id, "anchor-1") is a1
    assert repo.get_by_user_and_client_id(user.id, "missing") is None

    listed = repo.list_for_user_since(user.id)
    assert listed == [a1, a2]  # ordered by updated_at ASC

    after_a1 = repo.list_for_user_since(user.id, since=base)
    assert after_a1 == [a2]


def test_list_includes_tombstones(db_session):
    """Tombstoned (deleted) anchors must remain visible to the service."""
    user = UserRepository(db_session).create(email="t@example.com")
    repo = SessionAnchorRepository(db_session)

    tomb = SessionAnchor(
        user_id=user.id,
        client_anchor_id="tomb-1",
        anchor_text="",
        is_deleted=True,
        updated_at=datetime.now(timezone.utc),
    )
    repo.add(tomb)
    db_session.commit()

    assert tomb in repo.list_for_user_since(user.id)
