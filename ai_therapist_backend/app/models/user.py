from sqlalchemy import Boolean, Column, Integer, String, DateTime
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from app.db.base_class import Base


class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    firebase_uid = Column(String(128), unique=True, index=True, nullable=True)
    password_hash = Column(String, nullable=False)
    name = Column(String)
    profile_image_url = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    is_active = Column(Boolean, default=True)
    last_login = Column(DateTime(timezone=True), nullable=True)
    
    # Subscription fields
    subscription_tier = Column(String(20), default='none', nullable=False)  # 'none', 'basic', 'premium'
    subscription_expires_at = Column(DateTime(timezone=True), nullable=True)
    subscription_plan_id = Column(String(50), nullable=True)  # Google Play plan ID for flexibility
    
    # Relationships
    purchase_tokens = relationship("PurchaseToken", back_populates="user")