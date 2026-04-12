"""User identity repository — migrated from app/crud/user_identity.py."""
from __future__ import annotations

from typing import Optional, Protocol

from sqlalchemy.orm import Session

from app.models.user_identity import UserIdentity


class IUserIdentityRepository(Protocol):
    def get_by_provider_uid(self, *, provider: str, uid: str) -> Optional[UserIdentity]: ...
    def create(
        self,
        *,
        user_id: int,
        provider: str,
        uid: str,
        email: Optional[str] = None,
    ) -> UserIdentity: ...


class UserIdentityRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_by_provider_uid(self, *, provider: str, uid: str) -> Optional[UserIdentity]:
        return (
            self.db.query(UserIdentity)
            .filter(UserIdentity.provider == provider, UserIdentity.uid == uid)
            .first()
        )

    def create(
        self,
        *,
        user_id: int,
        provider: str,
        uid: str,
        email: Optional[str] = None,
    ) -> UserIdentity:
        identity = UserIdentity(
            user_id=user_id,
            provider=provider,
            uid=uid,
            email=email,
        )
        self.db.add(identity)
        self.db.commit()
        self.db.refresh(identity)
        return identity
