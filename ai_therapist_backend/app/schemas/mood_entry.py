from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, conint, constr


class MoodEntryIn(BaseModel):
    client_entry_id: constr(strip_whitespace=True, min_length=1, max_length=64)
    mood: conint(ge=0, le=5)
    notes: Optional[constr(max_length=512)] = None
    logged_at: datetime


class MoodEntryOut(BaseModel):
    client_entry_id: str
    server_id: str = Field(..., alias="id")
    mood: int
    notes: Optional[str] = None
    logged_at: datetime
    updated_at: datetime

    class Config:
        populate_by_name = True


class MoodEntryBatchUpsertRequest(BaseModel):
    entries: List[MoodEntryIn]


class MoodEntryBatchUpsertResponse(BaseModel):
    results: List[MoodEntryOut]


class MoodEntriesResponse(BaseModel):
    results: List[MoodEntryOut]
    next_before: Optional[str] = None
