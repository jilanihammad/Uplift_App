"""Shared fixtures for repository tests.

Uses an in-memory SQLite database with all SQLAlchemy models registered.
This is the first DB fixture in the project — the global conftest only
mocks encryption_service.
"""
from __future__ import annotations

from typing import Iterator

import pytest
from sqlalchemy import create_engine
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.sqlite.base import SQLiteTypeCompiler
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.orm import Session, sessionmaker

# Map JSONB → JSON so models that target Postgres can be created on SQLite
# in tests. Production behavior is unaffected; this only kicks in when the
# SQLite dialect compiles DDL.
@compiles(JSONB, "sqlite")
def _compile_jsonb_sqlite(type_, compiler, **kw):
    return "JSON"


# Importing app.models registers every model on Base.metadata before
# create_all runs. Without this the tables won't exist on the test engine.
import app.models  # noqa: F401  (side-effect import)
from app.db.base_class import Base


@pytest.fixture()
def db_session() -> Iterator[Session]:
    engine = create_engine("sqlite:///:memory:", future=True)
    Base.metadata.create_all(engine)
    TestSession = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    session = TestSession()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(engine)
        engine.dispose()
