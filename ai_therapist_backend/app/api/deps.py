# app/api/deps.py

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from sqlalchemy.sql import func
from typing import Optional
import logging

try:
    import firebase_admin
    from firebase_admin import auth as firebase_auth, credentials
except ImportError:
    firebase_admin = None
    firebase_auth = None

from app.db.session import get_db
from app.models.user import User

logger = logging.getLogger(__name__)
security = HTTPBearer()

# Initialize Firebase Admin SDK if not already done
if firebase_admin and not firebase_admin._apps:
    try:
        # In Cloud Run, this uses Application Default Credentials
        firebase_admin.initialize_app()
        logger.info("Firebase Admin SDK initialized with default credentials")
    except Exception as e:
        logger.warning(f"Failed to initialize Firebase Admin SDK: {e}")


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
) -> User:
    """Get current user from Firebase ID token with safe upsert"""
    
    if not firebase_auth:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Firebase authentication not configured"
        )
    
    try:
        # Verify Firebase ID token
        decoded_token = firebase_auth.verify_id_token(credentials.credentials)
        firebase_uid = decoded_token['uid']
        
        # Try to find user by firebase_uid first
        user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
        
        if not user:
            # Handle missing email (Apple Sign-In, phone auth, etc.)
            email = decoded_token.get('email')
            if not email:
                # Create a unique placeholder email
                email = f"{firebase_uid}@firebase.local"
            
            # Create new user with transaction safety
            user = User(
                firebase_uid=firebase_uid,
                email=email,
                name=decoded_token.get('name') or 'Anonymous',
                password_hash="firebase_auth_user",  # Placeholder
                profile_image_url=decoded_token.get('picture'),
                is_active=True,
                subscription_tier='none'  # Default tier
            )
            
            db.add(user)
            try:
                db.commit()
                db.refresh(user)
                logger.info(f"Created new user for Firebase UID: {firebase_uid}")
            except IntegrityError as e:
                # Handle race condition - another request created the user
                db.rollback()
                user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
                if not user:
                    # Check if it's an email conflict
                    if email and email != f"{firebase_uid}@firebase.local":
                        existing = db.query(User).filter(User.email == email).first()
                        if existing and not existing.firebase_uid:
                            # Update existing user with firebase_uid
                            existing.firebase_uid = firebase_uid
                            db.commit()
                            user = existing
                            logger.info(f"Linked Firebase UID to existing user: {email}")
                        else:
                            raise HTTPException(
                                status_code=status.HTTP_409_CONFLICT,
                                detail="Email already associated with another account"
                            )
                    else:
                        raise HTTPException(
                            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail="Failed to create user account"
                        )
        
        # Update last login
        user.last_login = func.now()
        db.commit()
        
        return user
        
    except firebase_auth.InvalidIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase ID token",
            headers={"WWW-Authenticate": "Bearer"}
        )
    except firebase_auth.ExpiredIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase ID token has expired",
            headers={"WWW-Authenticate": "Bearer"}
        )
    except Exception as e:
        logger.error(f"Auth error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication failed",
            headers={"WWW-Authenticate": "Bearer"}
        )


async def get_current_user_optional(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(HTTPBearer(auto_error=False)),
    db: Session = Depends(get_db)
) -> Optional[User]:
    """Get current user if authenticated, None otherwise"""
    if not credentials:
        return None
    
    try:
        return await get_current_user(credentials, db)
    except HTTPException:
        return None