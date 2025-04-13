from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Float, JSON
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from app.db.base_class import Base


class SubscriptionPlan(Base):
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    description = Column(String, nullable=False)
    price_monthly = Column(Float, nullable=False)
    price_yearly = Column(Float, nullable=False)
    features = Column(JSON, nullable=False)
    
    # Relationships
    subscriptions = relationship("Subscription", back_populates="plan")


class Subscription(Base):
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("user.id"), nullable=False)
    plan_id = Column(Integer, ForeignKey("subscriptionplan.id"), nullable=False)
    start_date = Column(DateTime(timezone=True), nullable=False)
    end_date = Column(DateTime(timezone=True), nullable=False)
    is_trial = Column(Boolean, default=False)
    payment_provider = Column(String, nullable=True)  # e.g., 'stripe', 'apple', 'google'
    payment_id = Column(String, nullable=True)  # External payment ID
    status = Column(String, default="active")  # active, canceled, expired
    
    # Relationships
    user = relationship("User", backref="subscriptions")
    plan = relationship("SubscriptionPlan", back_populates="subscriptions")