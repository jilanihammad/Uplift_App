from __future__ import annotations

from app.repositories import UserIdentityRepository, UserRepository


def test_provider_uid_lookup_returns_existing(db_session):
    user = UserRepository(db_session).create(email="x@example.com")
    repo = UserIdentityRepository(db_session)
    repo.create(user_id=user.id, provider="firebase", uid="abc123", email="x@example.com")

    found = repo.get_by_provider_uid(provider="firebase", uid="abc123")
    assert found is not None
    assert found.user_id == user.id

    missing = repo.get_by_provider_uid(provider="firebase", uid="nope")
    assert missing is None
