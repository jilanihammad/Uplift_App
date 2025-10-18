"""CRUD helpers for user identity mappings."""
from __future__ import annotations

from typing import Optional

from sqlalchemy.orm import Session

from app.models.user_identity import UserIdentity


def get_by_provider_uid(
    db: Session,
    *,
    provider: str,
    uid: str,
) -> Optional[UserIdentity]:
    return (
        db.query(UserIdentity)
        .filter(UserIdentity.provider == provider, UserIdentity.uid == uid)
        .first()
    )


def create(
    db: Session,
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
    db.add(identity)
    db.commit()
    db.refresh(identity)
    return identity
