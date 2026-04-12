from __future__ import annotations

from app.repositories import SessionRepository, UserRepository


def test_session_lifecycle(db_session):
    user = UserRepository(db_session).create(email="s@example.com")
    repo = SessionRepository(db_session)

    session = repo.create_session(user_id=user.id, title="Test", summary="initial")
    assert session.id is not None

    fetched = repo.get_session(session.id)
    assert fetched is session

    sessions = repo.get_sessions_by_user(user.id)
    assert sessions == [session]

    updated = repo.update_session(session.id, {"summary": "updated"})
    assert updated is not None
    assert updated.summary == "updated"

    deleted = repo.delete_session(session.id)
    assert deleted is True
    assert repo.get_session(session.id) is None


def test_messages_attached_to_session(db_session):
    user = UserRepository(db_session).create(email="m@example.com")
    repo = SessionRepository(db_session)
    session = repo.create_session(user_id=user.id, title="Msg Test")

    repo.add_message_to_session(session_id=session.id, content="hello", is_user_message=True)
    repo.add_messages_batch(
        session_id=session.id,
        messages=[
            {"content": "one", "is_user_message": False, "sequence": 1},
            {"content": "two", "is_user_message": False, "sequence": 2},
        ],
    )

    msgs = repo.get_messages_for_session(session.id)
    assert len(msgs) == 3
    assert {m.content for m in msgs} == {"hello", "one", "two"}
