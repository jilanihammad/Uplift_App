from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.models.user_profile import UserProfile


class ProfileConflictError(Exception):
    """Raised when optimistic concurrency checks fail."""


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def get_profile(db: Session, *, user_id: int) -> Optional[UserProfile]:
    """Fetch the profile for a user."""
    return db.query(UserProfile).filter(UserProfile.user_id == user_id).one_or_none()


def upsert_profile(
    db: Session,
    *,
    user_id: int,
    preferred_name: Optional[str],
    pronouns: Optional[str],
    locale: Optional[str],
    expected_version: Optional[int],
) -> UserProfile:
    """Create or update the user's profile with optimistic concurrency."""
    profile = get_profile(db, user_id=user_id)

    if profile is None:
        profile = UserProfile(
            user_id=user_id,
            preferred_name=preferred_name,
            pronouns=pronouns,
            locale=locale,
            version=1,
            updated_at=_utcnow(),
        )
        db.add(profile)
        db.commit()
        db.refresh(profile)
        return profile

    if expected_version is not None and profile.version != expected_version:
        raise ProfileConflictError("Profile version mismatch")

    profile.preferred_name = preferred_name
    profile.pronouns = pronouns
    profile.locale = locale
    profile.version = (profile.version or 0) + 1
    profile.updated_at = _utcnow()

    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile
