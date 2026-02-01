"""Session schemas for API requests/responses"""
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


class SessionCreate(BaseModel):
    """Schema for creating a new session"""
    title: Optional[str] = None


class SessionUpdate(BaseModel):
    """Schema for updating a session"""
    title: Optional[str] = None
    summary: Optional[str] = None


class SessionResponse(BaseModel):
    """Schema for session response"""
    id: str
    title: str
    summary: Optional[str] = None
    action_items: List[str] = Field(default_factory=list)
    created_at: str
    last_modified: str
    is_synced: bool = True
    
    class Config:
        from_attributes = True
