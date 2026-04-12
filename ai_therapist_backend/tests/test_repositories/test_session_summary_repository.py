from __future__ import annotations

from datetime import datetime, timezone

from app.models.session_summary import SessionSummary
from app.repositories import SessionSummaryRepository, UserRepository


def test_get_by_user_and_session(db_session):
    user = UserRepository(db_session).create(email="ss@example.com")
    repo = SessionSummaryRepository(db_session)

    summary = SessionSummary(
        user_id=user.id,
        session_id="sess-1",
        summary_json={"action_items": ["call back"], "summary": "first session"},
        updated_at=datetime.now(timezone.utc),
    )
    repo.add(summary)
    db_session.commit()

    assert repo.get_by_user_and_session(user.id, "sess-1") is summary
    assert repo.get_by_user_and_session(user.id, "missing") is None
