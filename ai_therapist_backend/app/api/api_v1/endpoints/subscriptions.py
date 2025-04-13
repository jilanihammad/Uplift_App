# app/api/api_v1/endpoints/subscriptions.py (enhanced webhook handler)

@router.post("/webhook", status_code=status.HTTP_200_OK)
async def webhook(
    *,
    request: Request,
    stripe_signature: str = Header(None),
    db: Session = Depends(deps.get_db),
) -> Any:
    """
    Handle Stripe webhook events.
    """
    try:
        # Get raw payload
        payload = await request.body()
        
        # Verify Stripe signature
        if not stripe_signature:
            return {"status": "error", "message": "No signature provided"}
        
        event = stripe.Webhook.construct_event(
            payload, stripe_signature, settings.STRIPE_WEBHOOK_SECRET
        )
        
        event_type = event["type"]
        logger.info(f"Processing Stripe webhook event: {event_type}")
        
        # Handle different event types
        if event_type == "checkout.session.completed":
            # Process successful checkout
            await process_checkout_session(db, event["data"]["object"])
            
        elif event_type == "customer.subscription.created":
            # Process new subscription
            await process_subscription_created(db, event["data"]["object"])
            
        elif event_type == "customer.subscription.updated":
            # Process subscription update
            await process_subscription_updated(db, event["data"]["object"])
            
        elif event_type == "customer.subscription.deleted":
            # Process subscription cancellation
            await process_subscription_deleted(db, event["data"]["object"])
            
        elif event_type == "invoice.payment_succeeded":
            # Process successful payment
            await process_invoice_paid(db, event["data"]["object"])
            
        elif event_type == "invoice.payment_failed":
            # Process failed payment
            await process_invoice_failed(db, event["data"]["object"])
        
        return {"status": "success", "event_type": event_type}
    except stripe.error.SignatureVerificationError:
        logger.error("Invalid Stripe signature")
        return {"status": "error", "message": "Invalid signature"}
    except Exception as e:
        logger.error(f"Error handling Stripe webhook: {str(e)}")
        return {"status": "error", "message": str(e)}

# Helper functions for webhook processing
async def process_checkout_session(db: Session, session: dict) -> None:
    """Process completed checkout session."""
    # Extract customer and metadata
    metadata = session.get("metadata", {})
    user_id = int(metadata.get("user_id", 0))
    plan_id = int(metadata.get("plan_id", 0))
    is_yearly = metadata.get("is_yearly", "false") == "true"
    
    # Verify user exists
    user = crud.user.get(db, id=user_id)
    if not user:
        logger.error(f"User not found: {user_id}")
        return
    
    # Get subscription details from session
    subscription_id = session.get("subscription")
    if subscription_id:
        try:
            stripe_sub = stripe.Subscription.retrieve(subscription_id)
            
            # Calculate end date
            end_timestamp = stripe_sub.current_period_end
            end_date = datetime.fromtimestamp(end_timestamp)
            
            # Create subscription in database
            crud.subscription.create(
                db,
                obj_in=schemas.SubscriptionCreate(
                    plan_id=plan_id,
                    is_trial=False,
                ),
                user_id=user_id,
            )
            
            # Update with subscription details
            subscription = crud.subscription.get_active_by_user_id(db, user_id=user_id)
            if subscription:
                crud.subscription.update(
                    db,
                    db_obj=subscription,
                    obj_in=schemas.SubscriptionUpdate(
                        end_date=end_date,
                        payment_id=subscription_id,
                        status="active",
                    ),
                )
            
            logger.info(f"Subscription created for user {user_id}")
            
        except Exception as e:
            logger.error(f"Error retrieving Stripe subscription: {str(e)}")
    else:
        logger.error("No subscription ID in checkout session")

# Implement other webhook processing functions...