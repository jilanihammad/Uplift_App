from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class AnchorView(BaseModel):
    id: str
    client_anchor_id: str
    anchor_text: str
    anchor_type: Optional[str] = None
    confidence: Optional[float] = Field(default=None, ge=0, le=1)
    is_deleted: bool
    last_seen_session_index: Optional[int] = None
    updated_at: datetime


class AnchorUpsertRequest(BaseModel):
    client_anchor_id: str
    anchor_text: str
    anchor_type: Optional[str] = None
    confidence: Optional[float] = Field(default=None, ge=0, le=1)
    last_seen_session_index: Optional[int] = None
    updated_at: Optional[datetime] = None

    class Config:
        extra = "forbid"


class AnchorDeleteRequest(BaseModel):
    client_anchor_id: str
    updated_at: Optional[datetime] = None

    class Config:
        extra = "forbid"


class AnchorMutationResponse(BaseModel):
    id: str
    updated_at: datetime
    changed: bool


class AnchorListResponse(BaseModel):
    items: List[AnchorView]
    next_page: Optional[str] = None
    server_time: datetime

    class Config:
        json_encoders = {
            datetime: lambda dt: dt.isoformat(),
        }
