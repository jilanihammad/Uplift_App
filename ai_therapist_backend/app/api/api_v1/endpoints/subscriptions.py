# app/api/api_v1/endpoints/subscriptions.py

import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api import deps
from app.models.user import User
from app.models.purchase_token import PurchaseToken
from app.db.session import get_db

# Configure logger
logger = logging.getLogger(__name__)

router = APIRouter()


class StorePurchaseTokenRequest(BaseModel):
    """Request model for storing purchase token mapping."""
    purchase_token: str
    subscription_id: str  # Google Play subscription ID (basic_chat or premium_voice_chat)


class SubscriptionStatusResponse(BaseModel):
    """Response model for subscription status."""
    subscription_tier: str
    subscription_expires_at: datetime | None
    subscription_plan_id: str | None


@router.post("/store-purchase-token", status_code=status.HTTP_200_OK)
async def store_purchase_token(
    *,
    request: StorePurchaseTokenRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(deps.get_current_user)
) -> dict[str, Any]:
    """
    Store purchase token mapping for Google Play webhook processing.
    
    This endpoint should be called immediately after a successful purchase
    on the client side to map the purchase token to the user account.
    """
    try:
        # Check if token already exists
        existing_token = db.query(PurchaseToken).filter(
            PurchaseToken.purchase_token == request.purchase_token
        ).first()
        
        if existing_token:
            logger.warning(f"Purchase token already exists: {request.purchase_token}")
            return {"status": "success", "message": "Token already stored"}
        
        # Create new purchase token mapping
        purchase_token_record = PurchaseToken(
            user_id=current_user.id,
            purchase_token=request.purchase_token,
            subscription_id=request.subscription_id
        )
        
        db.add(purchase_token_record)
        db.commit()
        
        logger.info(f"Stored purchase token for user {current_user.id}: {request.purchase_token}")
        
        return {
            "status": "success",
            "message": "Purchase token stored successfully"
        }
        
    except Exception as e:
        logger.error(f"Error storing purchase token: {str(e)}")
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to store purchase token"
        )


@router.get("/status", response_model=SubscriptionStatusResponse)
async def get_subscription_status(
    *,
    db: Session = Depends(get_db),
    current_user: User = Depends(deps.get_current_user)
) -> SubscriptionStatusResponse:
    """
    Get current user's subscription status.
    
    Returns the user's subscription tier, expiration date, and plan ID.
    """
    return SubscriptionStatusResponse(
        subscription_tier=current_user.subscription_tier,
        subscription_expires_at=current_user.subscription_expires_at,
        subscription_plan_id=current_user.subscription_plan_id
    )


@router.post("/cancel", status_code=status.HTTP_200_OK)
async def cancel_subscription(
    *,
    db: Session = Depends(get_db),
    current_user: User = Depends(deps.get_current_user)
) -> dict[str, Any]:
    """
    Mark subscription as canceled (client-side cancellation tracking).
    
    Note: This doesn't actually cancel with Google Play - that must be done
    through the Google Play Console or Play Developer API. This is just for
    client-side tracking until the webhook processes the actual cancellation.
    """
    try:
        # Just log the cancellation request - actual processing happens via webhook
        logger.info(f"User {current_user.id} requested subscription cancellation")
        
        return {
            "status": "success",
            "message": "Cancellation request logged. Processing will complete via webhook."
        }
        
    except Exception as e:
        logger.error(f"Error logging cancellation request: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to log cancellation request"
        )