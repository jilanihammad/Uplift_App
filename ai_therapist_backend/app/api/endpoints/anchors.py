from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.api.deps.auth import AuthenticatedUser, get_current_user
from app.db.session import get_db
from app.schemas import (
    AnchorDeleteRequest,
    AnchorListResponse,
    AnchorMutationResponse,
    AnchorUpsertRequest,
    AnchorView,
)
from app.services.anchor_service import delete_anchor, list_anchors_since, upsert_anchor

router = APIRouter()


def _parse_since(value: Optional[str]) -> Optional[datetime]:
    if value is None:
        return None
    try:
        if value.endswith("Z"):
            value = value.replace("Z", "+00:00")
        return datetime.fromisoformat(value)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid since timestamp") from exc


@router.get("", response_model=AnchorListResponse)
async def list_anchors(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
    since: Optional[str] = Query(default=None, description="ISO-8601 timestamp"),
    page_size: int = Query(default=100, ge=1, le=500),
) -> AnchorListResponse:
    since_dt = _parse_since(since)
    anchors = list_anchors_since(
        db,
        user_id=current_user.user.id,
        since=since_dt,
        limit=page_size,
    )
    items = [
        AnchorView(
            id=str(anchor.id),
            client_anchor_id=anchor.client_anchor_id,
            anchor_text=anchor.anchor_text,
            anchor_type=anchor.anchor_type,
            confidence=float(anchor.confidence) if anchor.confidence is not None else None,
            is_deleted=bool(anchor.is_deleted),
            last_seen_session_index=anchor.last_seen_session_index,
            updated_at=anchor.updated_at,
        )
        for anchor in anchors
    ]
    return AnchorListResponse(
        items=items,
        next_page=None,
        server_time=datetime.now(timezone.utc),
    )


@router.post(":upsert", response_model=AnchorMutationResponse)
async def upsert_anchor_endpoint(
    payload: AnchorUpsertRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AnchorMutationResponse:
    anchor, changed = upsert_anchor(
        db,
        user_id=current_user.user.id,
        client_anchor_id=payload.client_anchor_id,
        anchor_text=payload.anchor_text,
        anchor_type=payload.anchor_type,
        confidence=payload.confidence,
        last_seen_session_index=payload.last_seen_session_index,
        client_updated_at=payload.updated_at,
    )
    return AnchorMutationResponse(
        id=str(anchor.id),
        updated_at=anchor.updated_at,
        changed=changed,
    )


@router.post(":delete", response_model=AnchorMutationResponse)
async def delete_anchor_endpoint(
    payload: AnchorDeleteRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AnchorMutationResponse:
    anchor, changed = delete_anchor(
        db,
        user_id=current_user.user.id,
        client_anchor_id=payload.client_anchor_id,
        client_updated_at=payload.updated_at,
    )
    return AnchorMutationResponse(
        id=str(anchor.id),
        updated_at=anchor.updated_at,
        changed=changed,
    )
