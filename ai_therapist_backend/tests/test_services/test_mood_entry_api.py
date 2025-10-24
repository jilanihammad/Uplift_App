from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import AsyncGenerator

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.pool import StaticPool
from sqlalchemy.orm import Session as DbSession, sessionmaker

from app.api.deps.auth import AuthenticatedUser
from app.api.endpoints import mood_entries
from app.db.base_class import Base
from app.db.session import get_db
from app.models.mood_entry import MoodEntry
from app.models.user import User
from app.models.session import Session as SessionModel
from app.services.mood_entry_service import LOOKBACK_WINDOW
from app.api.endpoints.mood_entries import rate_limiter


@pytest.fixture()
def api_client() -> TestClient:
    engine = create_engine(
        "sqlite://",
        future=True,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SessionLocal = sessionmaker(bind=engine, future=True)
    from app.db import session as db_session_module
    db_session_module.engine = engine
    db_session_module.SessionLocal = SessionLocal
    Base.metadata.create_all(
        bind=db_session_module.engine,
        tables=[
            User.__table__,
            SessionModel.__table__,
            MoodEntry.__table__,
        ],
    )

    with SessionLocal() as session:
        session.add(User(id=1, email="api@example.com", password_hash="hash"))
        session.commit()

    async def override_get_db() -> AsyncGenerator[DbSession, None]:
        db = SessionLocal()
        try:
            yield db
        finally:
            db.close()

    dummy_user = AuthenticatedUser(
        user=User(id=1, email="api@example.com", password_hash="hash"),
        token="test",
        provider="test",
        payload={},
    )

    async def override_get_current_user() -> AuthenticatedUser:
        return dummy_user

    app = FastAPI()
    app.include_router(mood_entries.router, prefix="/api/v1/mood_entries")
    app.dependency_overrides[get_db] = override_get_db
    from app.api.deps.auth import get_current_user

    app.dependency_overrides[get_current_user] = override_get_current_user

    client = TestClient(app)
    try:
        yield client
    finally:
        rate_limiter._events.clear()


def test_batch_upsert_and_list(api_client: TestClient):
    payload = {
        "entries": [
            {
                "client_entry_id": "api-1",
                "mood": 4,
                "notes": "Feeling good",
                "logged_at": (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat(),
            }
        ]
    }

    response = api_client.post("/api/v1/mood_entries:batch_upsert", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["results"][0]["client_entry_id"] == "api-1"
    assert "updated_at" in body["results"][0]

    list_response = api_client.get("/api/v1/mood_entries")
    assert list_response.status_code == 200
    list_body = list_response.json()
    assert len(list_body["results"]) == 1
    assert list_body["results"][0]["client_entry_id"] == "api-1"


def test_batch_upsert_rejects_future_entry(api_client: TestClient):
    future_time = datetime.now(timezone.utc) + timedelta(days=8)
    payload = {
        "entries": [
            {
                "client_entry_id": "future",
                "mood": 2,
                "logged_at": future_time.isoformat(),
            }
        ]
    }
    response = api_client.post("/api/v1/mood_entries:batch_upsert", json=payload)
    assert response.status_code == 422
    assert response.json()["detail"]["field"] == "logged_at"


def test_batch_upsert_hits_rate_limit(api_client: TestClient):
    payload = {
        "entries": [
            {
                "client_entry_id": f"bulk-{i}",
                "mood": 1,
                "logged_at": (datetime.now(timezone.utc) - timedelta(minutes=i)).isoformat(),
            }
            for i in range(11)
        ]
    }
    response = api_client.post("/api/v1/mood_entries:batch_upsert", json=payload)
    assert response.status_code == 429


def test_list_with_invalid_token(api_client: TestClient):
    response = api_client.get("/api/v1/mood_entries", params={"before": "invalid"})
    assert response.status_code == 422


def test_list_clamps_since(api_client: TestClient):
    # Seed entries covering retention window
    now = datetime.now(timezone.utc)
    within_window = now - LOOKBACK_WINDOW + timedelta(days=1)
    payload = {
        "entries": [
            {
                "client_entry_id": "retained",
                "mood": 3,
                "logged_at": within_window.isoformat(),
            }
        ]
    }
    api_client.post("/api/v1/mood_entries:batch_upsert", json=payload)
    # Request since far in the past; should clamp and return entry
    response = api_client.get(
        "/api/v1/mood_entries",
        params={"since": (now - timedelta(days=120)).isoformat()},
    )
    assert response.status_code == 200
    assert response.json()["results"][0]["client_entry_id"] == "retained"
