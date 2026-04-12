from __future__ import annotations

from datetime import datetime, timezone

from app.models.user_profile import UserProfile
from app.repositories import UserProfileRepository, UserRepository


def test_get_by_user_id(db_session):
    user = UserRepository(db_session).create(email="p@example.com")
    repo = UserProfileRepository(db_session)

    assert repo.get_by_user_id(user.id) is None

    profile = UserProfile(
        user_id=user.id,
        preferred_name="Pat",
        version=1,
        updated_at=datetime.now(timezone.utc),
    )
    repo.add(profile)
    db_session.commit()

    assert repo.get_by_user_id(user.id) is profile
    assert repo.get_by_user_id(user.id + 9999) is None
