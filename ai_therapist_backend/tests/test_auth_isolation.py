from __future__ import annotations

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.deps.auth import _get_or_create_user
from app.db.base_class import Base
from app.models.user import User
from app.models.user_identity import UserIdentity


@pytest.fixture()
def db_session() -> Session:
    engine = create_engine(
        "sqlite://",
        future=True,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[
            User.__table__,
            UserIdentity.__table__,
        ],
    )
    SessionLocal = sessionmaker(bind=engine, future=True)
    with SessionLocal() as session:
        yield session


def test_distinct_providers_create_distinct_users(db_session: Session) -> None:
    google_user = _get_or_create_user(
        db_session,
        provider="google.com",
        uid="google-uid-123",
        email="alice@example.com",
        name="Alice",
    )

    phone_user = _get_or_create_user(
        db_session,
        provider="phone",
        uid="phone-uid-123",
        email="alice@example.com",
        name="Alice",
    )

    assert google_user.id != phone_user.id
    assert google_user.email != phone_user.email

    assert {identity.provider for identity in google_user.identities} == {"google.com"}
    assert {identity.provider for identity in phone_user.identities} == {"phone"}
    assert google_user.identities[0].email == "alice@example.com"
    assert phone_user.identities[0].email == "alice@example.com"


def test_existing_identity_is_reused(db_session: Session) -> None:
    first = _get_or_create_user(
        db_session,
        provider="google.com",
        uid="google-uid-123",
        email="alice@example.com",
        name="Alice",
    )

    second = _get_or_create_user(
        db_session,
        provider="google.com",
        uid="google-uid-123",
        email="alice+updated@example.com",
        name="Alice",
    )

    assert first.id == second.id

    db_session.refresh(first)
    identity = first.identities[0]
    assert identity.email == "alice+updated@example.com"
