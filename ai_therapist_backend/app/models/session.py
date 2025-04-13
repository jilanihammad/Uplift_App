from sqlalchemy import Column, Integer, DateTime, ForeignKey, String, SmallInteger
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from app.db.base_class import Base


class Session(Base):
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("user.id"), nullable=False)
    start_time = Column(DateTime(timezone=True), server_default=func.now())
    end_time = Column(DateTime(timezone=True), nullable=True)
    summary = Column(String, nullable=True)
    mood_before = Column(SmallInteger, nullable=True)  # Scale 1-5
    mood_after = Column(SmallInteger, nullable=True)   # Scale 1-5
    
    # Relationships
    user = relationship("User", backref="sessions")
    messages = relationship("Message", back_populates="session", cascade="all, delete-orphan")
    action_plans = relationship("ActionPlan", back_populates="session", cascade="all, delete-orphan")