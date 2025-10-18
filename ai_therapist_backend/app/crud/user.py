"""CRUD helpers for user management."""
from __future__ import annotations

import logging
from typing import Optional
from uuid import uuid4

from sqlalchemy.orm import Session

from app.models.user import User
from app.core.security import get_password_hash


logger = logging.getLogger(__name__)


def get_by_id(db: Session, user_id: int) -> Optional[User]:
    return db.query(User).filter(User.id == user_id).first()


def get_by_email(db: Session, email: str) -> Optional[User]:
    return db.query(User).filter(User.email == email).first()


def create(
    db: Session,
    *,
    email: str,
    name: Optional[str] = None,
    password: Optional[str] = None,
    is_active: bool = True,
) -> User:
    raw_password = (password or uuid4().hex)
    # bcrypt only considers the first 72 bytes; truncate to avoid passlib errors
    raw_password = raw_password[:72]
    hashed_password = get_password_hash(raw_password)
    user = User(
        email=email,
        password_hash=hashed_password,
        name=name,
        is_active=is_active,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
