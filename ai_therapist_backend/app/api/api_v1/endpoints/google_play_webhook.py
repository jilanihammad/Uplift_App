# app/api/api_v1/endpoints/google_play_webhook.py

import base64
import json
import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Request, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api import deps
from app.core.config import settings
from app.models.user import User
from app.models.purchase_token import PurchaseToken
from app.db.session import get_db

# Configure logger
logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("/google-webhook", status_code=200)
async def handle_google_play_rtdn(
    request: Request,
    db: Session = Depends(get_db)
) -> dict[str, Any]:
    """
    Handle Google Play Real-time Developer Notifications (RTDN).
    
    This endpoint receives notifications from Google Play about subscription changes:
    - New purchases
    - Renewals
    - Cancellations
    - Expiry
    - Upgrades/downgrades
    """
    try:
        # Get the raw request body
        body = await request.body()
        
        # Parse the Google Cloud Pub/Sub message
        try:
            pubsub_message = json.loads(body)
            logger.info(f"Received Pub/Sub message: {pubsub_message}")
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse Pub/Sub message: {e}")
            return {"status": "error", "message": "Invalid JSON format"}
        
        # Extract and decode the message data
        message = pubsub_message.get("message", {})
        if not message:
            logger.warning("No message found in Pub/Sub payload")
            return {"status": "success", "message": "No message to process"}
        
        # Decode the base64-encoded data
        encoded_data = message.get("data", "")
        if not encoded_data:
            logger.warning("No data found in message")
            return {"status": "success", "message": "No data to process"}
        
        try:
            decoded_data = base64.b64decode(encoded_data).decode('utf-8')
            notification_data = json.loads(decoded_data)
            logger.info(f"Decoded notification data: {notification_data}")
        except Exception as e:
            logger.error(f"Failed to decode notification data: {e}")
            return {"status": "error", "message": "Failed to decode notification data"}
        
        # Process the notification based on type
        if "subscriptionNotification" in notification_data:
            await process_subscription_notification(db, notification_data["subscriptionNotification"])
        elif "oneTimeProductNotification" in notification_data:
            # Handle one-time purchases if needed
            logger.info("One-time product notification received (not processing)")
        else:
            logger.warning(f"Unknown notification type: {notification_data}")
        
        return {"status": "success", "message": "Notification processed"}
        
    except Exception as e:
        logger.error(f"Error processing Google Play webhook: {str(e)}")
        # Return 200 to prevent Google from retrying
        return {"status": "error", "message": str(e)}


async def process_subscription_notification(db: Session, notification: dict) -> None:
    """
    Process Google Play subscription notification.
    
    Notification types:
    - SUBSCRIPTION_PURCHASED (1)
    - SUBSCRIPTION_CANCELED (2)
    - SUBSCRIPTION_ON_HOLD (5)
    - SUBSCRIPTION_IN_GRACE_PERIOD (6)
    - SUBSCRIPTION_RESTARTED (7)
    - SUBSCRIPTION_PRICE_CHANGE_CONFIRMED (8)
    - SUBSCRIPTION_DEFERRED (9)
    - SUBSCRIPTION_PAUSED (10)
    - SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED (11)
    - SUBSCRIPTION_REVOKED (12)
    - SUBSCRIPTION_EXPIRED (13)
    """
    try:
        # Extract notification details
        version = notification.get("version")
        notification_type = notification.get("notificationType")
        purchase_token = notification.get("purchaseToken")
        subscription_id = notification.get("subscriptionId")
        
        logger.info(f"Processing subscription notification: type={notification_type}, "
                   f"subscription={subscription_id}, token={purchase_token}")
        
        if not purchase_token or not subscription_id:
            logger.error("Missing required fields in subscription notification")
            return
        
        # Map subscription_id to our tier system
        tier_mapping = {
            "basic_chat": "basic",
            "premium_voice_chat": "premium"
        }
        
        subscription_tier = tier_mapping.get(subscription_id, "none")
        
        # Find user by some method (you'll need to implement user lookup by purchase token)
        # For now, we'll need to store the purchase token when the purchase is made
        # This is a simplified version - you might need a separate table to map tokens to users
        user = await find_user_by_purchase_context(db, purchase_token, subscription_id)
        
        if not user:
            logger.error(f"User not found for purchase token: {purchase_token}")
            return
        
        # Process based on notification type
        if notification_type == 1:  # SUBSCRIPTION_PURCHASED
            await handle_subscription_purchased(db, user, subscription_tier, notification)
        elif notification_type == 2:  # SUBSCRIPTION_CANCELED
            await handle_subscription_canceled(db, user, notification)
        elif notification_type == 13:  # SUBSCRIPTION_EXPIRED
            await handle_subscription_expired(db, user, notification)
        elif notification_type in [5, 6]:  # ON_HOLD or GRACE_PERIOD
            await handle_subscription_grace_period(db, user, notification)
        elif notification_type == 7:  # SUBSCRIPTION_RESTARTED
            await handle_subscription_restarted(db, user, subscription_tier, notification)
        else:
            logger.info(f"Unhandled notification type: {notification_type}")
    
    except Exception as e:
        logger.error(f"Error processing subscription notification: {str(e)}")


async def find_user_by_purchase_context(db: Session, purchase_token: str, subscription_id: str) -> User | None:
    """
    Find user by purchase context using the purchase_tokens mapping table.
    
    This function looks up the user associated with a purchase token that was
    stored when the purchase was initiated on the client side.
    """
    try:
        # Query the purchase_tokens table to find the user
        purchase_token_record = db.query(PurchaseToken).filter(
            PurchaseToken.purchase_token == purchase_token
        ).first()
        
        if not purchase_token_record:
            logger.warning(f"No purchase token record found for token: {purchase_token}")
            return None
        
        # Return the associated user
        user = db.query(User).filter(User.id == purchase_token_record.user_id).first()
        
        if user:
            logger.info(f"Found user {user.id} for purchase token: {purchase_token}")
        else:
            logger.error(f"User {purchase_token_record.user_id} not found for purchase token: {purchase_token}")
        
        return user
        
    except Exception as e:
        logger.error(f"Error looking up user by purchase token: {str(e)}")
        return None


async def handle_subscription_purchased(db: Session, user: User, tier: str, notification: dict) -> None:
    """Handle new subscription purchase."""
    try:
        # Update user's subscription tier
        user.subscription_tier = tier
        user.subscription_plan_id = notification.get("subscriptionId")
        
        # Set expiry date (you might need to call Google Play API for accurate dates)
        # For now, set to None (will be updated by renewal notifications)
        user.subscription_expires_at = None
        
        db.commit()
        logger.info(f"User {user.id} subscription updated to {tier}")
        
    except Exception as e:
        db.rollback()
        logger.error(f"Error updating user subscription: {str(e)}")


async def handle_subscription_canceled(db: Session, user: User, notification: dict) -> None:
    """Handle subscription cancellation."""
    try:
        # Don't immediately downgrade - let it expire naturally
        # Just log the cancellation
        logger.info(f"User {user.id} subscription canceled, will expire at: {user.subscription_expires_at}")
        
    except Exception as e:
        logger.error(f"Error handling subscription cancellation: {str(e)}")


async def handle_subscription_expired(db: Session, user: User, notification: dict) -> None:
    """Handle subscription expiry."""
    try:
        # Downgrade user to free tier
        user.subscription_tier = "none"
        user.subscription_plan_id = None
        user.subscription_expires_at = None
        
        db.commit()
        logger.info(f"User {user.id} subscription expired and downgraded to free tier")
        
    except Exception as e:
        db.rollback()
        logger.error(f"Error handling subscription expiry: {str(e)}")


async def handle_subscription_grace_period(db: Session, user: User, notification: dict) -> None:
    """Handle subscription in grace period or on hold."""
    try:
        # Keep subscription active during grace period
        logger.info(f"User {user.id} subscription in grace period")
        
    except Exception as e:
        logger.error(f"Error handling subscription grace period: {str(e)}")


async def handle_subscription_restarted(db: Session, user: User, tier: str, notification: dict) -> None:
    """Handle subscription restart after pause/hold."""
    try:
        # Reactivate subscription
        user.subscription_tier = tier
        user.subscription_plan_id = notification.get("subscriptionId")
        
        db.commit()
        logger.info(f"User {user.id} subscription restarted with tier {tier}")
        
    except Exception as e:
        db.rollback()
        logger.error(f"Error handling subscription restart: {str(e)}")