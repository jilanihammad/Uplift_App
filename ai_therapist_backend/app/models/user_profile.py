import uuid
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.db.base_class import Base


class UserProfile(Base):
    __tablename__ = "user_profiles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, unique=True)
    preferred_name = Column(String, nullable=True)
    pronouns = Column(String, nullable=True)
    locale = Column(String, nullable=True)
    version = Column(Integer, nullable=False, server_default="1")
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
