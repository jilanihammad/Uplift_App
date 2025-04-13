# scripts/seed_db.py

import logging
import json
from sqlalchemy.orm import Session
from app.db.session import SessionLocal
from app.models.subscription import SubscriptionPlan
from app.models.user import User
from app.core.security import get_password_hash
from app.core.config import settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def seed_db() -> None:
    db = SessionLocal()
    seed_subscription_plans(db)
    seed_demo_account(db)
    db.close()

def seed_subscription_plans(db: Session) -> None:
    # Check if plans already exist
    if db.query(SubscriptionPlan).count() > 0:
        logger.info("Subscription plans already exist")
        return
    
    # Create subscription plans
    basic_plan = SubscriptionPlan(
        name="Basic",
        description="Access to AI therapist with basic features",
        price_monthly=9.99,
        price_yearly=99.99,
        features={
            "unlimited_sessions": True,
            "chat_history": "1 year",
            "action_plans": True,
            "notes": True,
            "reminders": True,
            "voice_synthesis": True,
            "priority_response": False,
            "advanced_insights": False,
        }
    )
    
    premium_plan = SubscriptionPlan(
        name="Premium",
        description="Full access to all AI therapist features",
        price_monthly=19.99,
        price_yearly=199.99,
        features={
            "unlimited_sessions": True,
            "chat_history": "Unlimited",
            "action_plans": True,
            "notes": True,
            "reminders": True,
            "voice_synthesis": True,
            "priority_response": True,
            "advanced_insights": True,
        }
    )
    
    db.add(basic_plan)
    db.add(premium_plan)
    db.commit()
    
    logger.info("Subscription plans created")

def seed_demo_account(db: Session) -> None:
    # Check if demo account already exists
    demo_email = "demo@example.com"
    if db.query(User).filter(User.email == demo_email).count() > 0:
        logger.info("Demo account already exists")
        return
    
    # Create demo user
    demo_user = User(
        email=demo_email,
        password_hash=get_password_hash("password123"),
        name="Demo User",
        is_active=True
    )
    
    db.add(demo_user)
    db.commit()
    
    logger.info("Demo account created")

if __name__ == "__main__":
    logger.info("Seeding database with initial data")
    seed_db()
    logger.info("Database seeding completed")