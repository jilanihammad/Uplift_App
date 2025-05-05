#!/usr/bin/env python
"""
Create a test user in the database.
"""
import sys
import os
import logging
from datetime import datetime
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import hashlib
import uuid

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add the parent directory to the path so we can import app
sys.path.append(os.path.abspath('.'))

try:
    from app.core.config import settings
    from app.db.base import Base
    from app.models.user import User
    from app.models.session import Session
except ImportError as e:
    logger.error(f"Error importing modules: {e}")
    sys.exit(1)

def create_test_user():
    """Create a test user in the database."""
    try:
        # Create engine and session
        engine = create_engine(settings.SQLALCHEMY_DATABASE_URI, pool_pre_ping=True)
        SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
        db = SessionLocal()
        
        # Create tables if they don't exist
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created if they didn't exist")
        
        # Check if test user already exists
        test_email = "test@example.com"
        existing_user = db.query(User).filter(User.email == test_email).first()
        
        if existing_user:
            logger.info(f"Test user already exists with ID: {existing_user.id}")
            user_id = existing_user.id
        else:
            # Create a simple password hash
            password = "password123"
            password_hash = hashlib.sha256(password.encode()).hexdigest()
            
            # Create test user
            user = User(
                email=test_email,
                password_hash=password_hash,
                name="Test User",
                is_active=True,
                last_login=datetime.now()
            )
            
            # Add user to database
            db.add(user)
            db.commit()
            db.refresh(user)
            logger.info(f"Created test user with ID: {user.id}")
            user_id = user.id
        
        # Create a test session
        session_title = f"Test Session {uuid.uuid4().hex[:8]}"
        test_session = Session(
            user_id=user_id,
            title=session_title,
            summary="This is a test session created by the create_test_user script.",
            start_time=datetime.now()
        )
        
        # Add session to database
        db.add(test_session)
        db.commit()
        logger.info(f"Created test session with title: {session_title}")
        
        return True
    except Exception as e:
        logger.error(f"Error creating test user: {e}")
        return False
    finally:
        db.close()

if __name__ == "__main__":
    success = create_test_user()
    if success:
        logger.info("Test user creation completed successfully.")
    else:
        logger.error("Test user creation failed.")
        sys.exit(1) 