import uuid
from sqlalchemy import Column, Integer, String, Boolean, Numeric, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.db.base_class import Base


class SessionAnchor(Base):
    __tablename__ = "session_anchors"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    client_anchor_id = Column(String, nullable=False)
    anchor_text = Column(String, nullable=False)
    anchor_type = Column(String, nullable=True)
    confidence = Column(Numeric(3, 2), nullable=True)
    is_deleted = Column(Boolean, nullable=False, server_default="false")
    last_seen_session_index = Column(Integer, nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
