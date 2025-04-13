from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from app.db.base_class import Base


class Reminder(Base):
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("user.id"), nullable=False)
    action_plan_id = Column(Integer, ForeignKey("actionplan.id"), nullable=True)
    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    scheduled_time = Column(DateTime(timezone=True), nullable=False)
    is_completed = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    user = relationship("User", backref="reminders")
    action_plan = relationship("ActionPlan", back_populates="reminders")