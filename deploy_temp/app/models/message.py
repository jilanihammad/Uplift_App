from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from app.db.base_class import Base


class Message(Base):
    __tablename__ = "messages"
    
    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("sessions.id"), nullable=False, index=True)
    content = Column(Text, nullable=False)
    is_user_message = Column(Boolean, default=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    audio_url = Column(String, nullable=True)
    sequence = Column(Integer, nullable=True)
    
    # Relationships
    session = relationship("Session", back_populates="messages")