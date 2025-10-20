from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ProfileResponse(BaseModel):
    preferred_name: Optional[str] = None
    pronouns: Optional[str] = None
    locale: Optional[str] = None
    version: int = Field(ge=0)
    updated_at: Optional[datetime] = None


class ProfileUpdateRequest(BaseModel):
    preferred_name: Optional[str] = None
    pronouns: Optional[str] = None
    locale: Optional[str] = None
    version: Optional[int] = Field(default=None, ge=0)

    class Config:
        extra = "forbid"
