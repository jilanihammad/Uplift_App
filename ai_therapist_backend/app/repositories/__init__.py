"""Repository layer.

Patterns
--------
- Each repository is a class that takes a per-request SQLAlchemy ``Session``
  via constructor.
- Each module colocates the repository class with its Protocol interface
  (e.g., ``UserRepository`` + ``IUserRepository`` in ``user_repository.py``).
- DI factories below produce repositories suitable for FastAPI ``Depends``.
- Repositories migrated from the legacy ``app/crud/`` folder preserve
  commit-on-write behavior for backward compatibility; new repositories
  follow the no-commit policy documented in ``base.py``.
"""
from __future__ import annotations

from fastapi import Depends
from sqlalchemy.orm import Session

from app.db.session import get_db

from .reminder_repository import (
    IReminderRepository,
    ReminderRepository,
    SESSION_REMINDER_TITLE,
)
from .session_repository import ISessionRepository, SessionRepository
from .user_identity_repository import (
    IUserIdentityRepository,
    UserIdentityRepository,
)
from .user_repository import IUserRepository, UserRepository

__all__ = [
    "IReminderRepository",
    "ReminderRepository",
    "SESSION_REMINDER_TITLE",
    "ISessionRepository",
    "SessionRepository",
    "IUserIdentityRepository",
    "UserIdentityRepository",
    "IUserRepository",
    "UserRepository",
    "get_user_repository",
    "get_user_identity_repository",
    "get_session_repository",
    "get_reminder_repository",
]


def get_user_repository(db: Session = Depends(get_db)) -> IUserRepository:
    return UserRepository(db)


def get_user_identity_repository(db: Session = Depends(get_db)) -> IUserIdentityRepository:
    return UserIdentityRepository(db)


def get_session_repository(db: Session = Depends(get_db)) -> ISessionRepository:
    return SessionRepository(db)


def get_reminder_repository(db: Session = Depends(get_db)) -> IReminderRepository:
    return ReminderRepository(db)
