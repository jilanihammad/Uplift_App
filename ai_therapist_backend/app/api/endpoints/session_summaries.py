from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps.auth import AuthenticatedUser, get_current_user
from app.db.session import get_db
from app.schemas import (
    SessionSummaryMutationResponse,
    SessionSummaryUpsertRequest,
)
from app.services.session_summary_service import upsert_session_summary

router = APIRouter()


@router.post(":upsert", response_model=SessionSummaryMutationResponse)
async def upsert_session_summary_endpoint(
    payload: SessionSummaryUpsertRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SessionSummaryMutationResponse:
    summary, changed = upsert_session_summary(
        db,
        user_id=current_user.user.id,
        session_id=payload.session_id,
        summary_json=payload.summary_json,
        client_updated_at=payload.updated_at,
    )
    return SessionSummaryMutationResponse(
        id=str(summary.id),
        updated_at=summary.updated_at,
        changed=changed,
    )
