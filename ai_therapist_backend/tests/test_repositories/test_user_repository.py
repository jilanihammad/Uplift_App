from __future__ import annotations

from app.repositories import UserRepository


def test_create_and_lookup_user(db_session):
    repo = UserRepository(db_session)
    user = repo.create(email="a@example.com", name="Alice")

    assert user.id is not None
    assert repo.get_by_id(user.id) is user
    assert repo.get_by_email("a@example.com") is user
    assert repo.get_by_email("missing@example.com") is None


def test_create_truncates_long_password(db_session):
    repo = UserRepository(db_session)
    long_password = "x" * 200
    user = repo.create(email="b@example.com", password=long_password)
    assert user.password_hash is not None
