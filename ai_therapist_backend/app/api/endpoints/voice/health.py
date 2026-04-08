"""
Health check and rate-limit status endpoints.

Contains:
- /ping health check
- /rate-limit-status rate limit information
"""
import logging
from datetime import datetime, timezone
from typing import Dict, Any

from fastapi import APIRouter, HTTPException, Query
from jose import jwt, JWTError

from app.core.config import settings
from .rate_limiter import text_rate_limiter

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/ping")
async def ping_endpoint():
    """Health check endpoint"""
    return {"status": "alive", "timestamp": datetime.now().isoformat()}


@router.get("/rate-limit-status")
async def get_rate_limit_status(
    token: str = Query(..., description="JWT authentication token")
):
    """
    Get current rate limit status for the authenticated user
    Useful for frontend to display rate limit information
    """
    try:
        user_id = None

        # Try Firebase verification first
        try:
            import firebase_admin
            from firebase_admin import auth as firebase_auth

            if firebase_admin._apps:
                decoded_token = firebase_auth.verify_id_token(token)
                user_id = decoded_token.get('uid') or decoded_token.get('user_id') or decoded_token.get('sub')
                logger.info(f"Rate limit check: Firebase auth successful for user: {user_id}")
        except Exception as firebase_error:
            logger.info(f"Rate limit check: Firebase verification failed: {firebase_error}")

            # Fall back to manual RS256 verification
            try:
                import requests

                google_keys_url = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
                response = requests.get(google_keys_url, timeout=10)
                google_public_keys = response.json()

                unverified_header = jwt.get_unverified_header(token)
                kid = unverified_header.get('kid')

                if kid and kid in google_public_keys:
                    public_key = google_public_keys[kid]
                    payload = jwt.decode(
                        token,
                        public_key,
                        algorithms=["RS256"],
                        audience="upliftapp-cd86e",
                        issuer="https://securetoken.google.com/upliftapp-cd86e"
                    )
                    user_id = payload.get('user_id') or payload.get('sub')
                    logger.info(f"Rate limit check: Manual RS256 auth successful for user: {user_id}")
            except Exception as rs256_error:
                logger.info(f"Rate limit check: Manual RS256 verification failed: {rs256_error}")

                # Fall back to local HS256
                payload = jwt.decode(
                    token,
                    settings.SECRET_KEY,
                    algorithms=["HS256"]
                )

                user_id = payload.get("sub")

                # Check token expiration for local tokens
                exp = payload.get("exp")
                current_time = datetime.now(timezone.utc).timestamp()

                if exp and current_time > exp:
                    raise HTTPException(status_code=401, detail="Local token expired")

                logger.info(f"Rate limit check: Local HS256 auth successful for user: {user_id}")

        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token - missing user ID")

        # Get rate limit status
        status = await text_rate_limiter.get_user_status(user_id)

        return {
            "user_id": user_id,
            "rate_limit_status": status,
            "timestamp": datetime.now().isoformat()
        }

    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except JWTError as e:
        logger.warning(f"JWT decode error in rate limit status: {str(e)}")
        raise HTTPException(status_code=401, detail="Invalid token")
    except Exception as e:
        logger.error(f"Error getting rate limit status: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")
