"""User repository — migrated from app/crud/user.py.

Preserves legacy commit-on-write behavior for compatibility with existing
callers in app/api/deps/auth.py. This will be normalized to the no-commit
policy when services are rewired (Uplift_App-4xc).
"""
from __future__ import annotations

import logging
from typing import Optional, Protocol
from uuid import uuid4

from sqlalchemy.orm import Session

from app.core.security import get_password_hash
from app.models.user import User

logger = logging.getLogger(__name__)


class IUserRepository(Protocol):
    def get_by_id(self, user_id: int) -> Optional[User]: ...
    def get_by_email(self, email: str) -> Optional[User]: ...
    def create(
        self,
        *,
        email: str,
        name: Optional[str] = None,
        password: Optional[str] = None,
        is_active: bool = True,
    ) -> User: ...


class UserRepository:
    """Concrete IUserRepository backed by SQLAlchemy."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def get_by_id(self, user_id: int) -> Optional[User]:
        return self.db.query(User).filter(User.id == user_id).first()

    def get_by_email(self, email: str) -> Optional[User]:
        return self.db.query(User).filter(User.email == email).first()

    def create(
        self,
        *,
        email: str,
        name: Optional[str] = None,
        password: Optional[str] = None,
        is_active: bool = True,
    ) -> User:
        raw_password = (password or uuid4().hex)[:72]
        hashed_password = get_password_hash(raw_password)
        user = User(
            email=email,
            password_hash=hashed_password,
            name=name,
            is_active=is_active,
        )
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        return user
