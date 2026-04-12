"""User profile repository.

Profile is 1:1 with user (``user_id`` is unique). Repo exposes a read-only
fetch; the service owns version increments for optimistic concurrency.
"""
from __future__ import annotations

from typing import Optional, Protocol
from uuid import UUID

from sqlalchemy.orm import Session

from app.models.user_profile import UserProfile

from .base import BaseRepository


class IUserProfileRepository(Protocol):
    def get_by_user_id(self, user_id: int) -> Optional[UserProfile]: ...
    def add(self, entity: UserProfile) -> UserProfile: ...


class UserProfileRepository(BaseRepository[UserProfile, UUID]):
    model = UserProfile

    def get_by_user_id(self, user_id: int) -> Optional[UserProfile]:
        return (
            self.db.query(UserProfile)
            .filter(UserProfile.user_id == user_id)
            .one_or_none()
        )
