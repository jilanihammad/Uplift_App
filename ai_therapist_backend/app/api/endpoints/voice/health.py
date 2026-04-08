"""
Health check and rate-limit status endpoints.

Contains:
- /ping health check
- /rate-limit-status rate limit information
"""
import logging
from datetime import datetime

from fastapi import APIRouter, HTTPException, Query

from app.api.deps.auth import _verify_token
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
        result = _verify_token(token)
        if not result:
            raise HTTPException(status_code=401, detail="Invalid token")

        payload, provider = result
        user_id = payload.get("uid") or payload.get("user_id") or payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token - missing user ID")

        status = await text_rate_limiter.get_user_status(user_id)

        return {
            "user_id": user_id,
            "rate_limit_status": status,
            "timestamp": datetime.now().isoformat()
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Error getting rate limit status: %s", e)
        raise HTTPException(status_code=500, detail="Internal server error")
