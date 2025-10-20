from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from pydantic import BaseModel


class SessionSummaryUpsertRequest(BaseModel):
    session_id: str
    summary_json: Dict[str, Any]
    updated_at: Optional[datetime] = None

    class Config:
        extra = "forbid"


class SessionSummaryMutationResponse(BaseModel):
    id: str
    updated_at: datetime
    changed: bool
