# Subscription Implementation Plan - AI Therapist App (Lightweight MVP)

## Overview

This plan implements a minimal two-tier subscription system:
- **Basic Tier**: Chat-only therapy sessions
- **Premium Tier**: Voice + chat therapy sessions (current functionality)

**MVP-First Approach**: Start with the absolute minimum to prove the concept works, then iterate post-launch.

## Architecture Decision

Following the simplified Android/iOS approach with:
- Single subscription with two base plans in Play Console
- Client-side tier caching for instant feature gating
- RTDN webhook for backend sync (no polling or middleware)
- Auto-restore on cold start + manual "Restore Purchases" button
- Remote config flag for instant rollback
- **Play Billing v6+** via `in_app_purchase` ≥ 3.2 (required for Google compliance)

## Phase 1: Core Implementation (Day 1)

### 1.1 Single SubscriptionManager Class
**What to build:**
```dart
// lib/services/subscription_manager.dart
class SubscriptionManager {
  final InAppPurchase _iap = InAppPurchase.instance;
  final _tierController = StreamController<SubscriptionTier>.broadcast();
  
  Stream<SubscriptionTier> get tierStream => _tierController.stream;
  SubscriptionTier get currentTier => _cachedTier;
  
  Future<void> initialize();
  Future<void> checkSubscriptionStatus(); // Auto-called on cold start
  Future<void> purchaseSubscription(String planId);
  Future<void> restorePurchases(); // Manual restore button
  void openManageSubscriptions(); // Deep link to Play Store
  
  // Auto-restore on cold start (adds ~5ms)
  Future<void> autoRestoreOnStartup() async {
    if (_iap.isAvailable()) {
      await _iap.queryPurchaseDetails(toSet([subscriptionId]));
    }
  }
}
```

**Testing before proceeding:**
- [ ] Create test harness that simulates tier changes
- [ ] Verify Stream<SubscriptionTier> updates properly
- [ ] Test with mock BillingClient responses
- [ ] Ensure no crashes with billing unavailable

### 1.2 Feature Gating Integration
**What to build:**
```dart
// In existing VoiceSessionBloc or ChatScreen
final tier = subscriptionManager.currentTier;
final canUseVoice = tier == SubscriptionTier.premium;

// Hide voice button if basic tier
if (!canUseVoice) {
  // Show upgrade prompt instead of voice button
}
```

**Testing checkpoint:**
- [ ] Hardcode different tiers and verify voice button visibility
- [ ] Test session creation with different tiers
- [ ] Ensure chat mode works for all tiers
- [ ] Deploy to test device and verify gating works

## Phase 2: Minimal Data Model (Day 2)

### 2.1 Subscription Data Storage
**What to build:**
```dart
// lib/models/subscription_tier.dart
enum SubscriptionTier { none, basic, premium }

// Add to encrypted SharedPreferences (single source of truth)
Future<void> _cacheSubscriptionData({
  required SubscriptionTier tier,
  required String? planId, // Cache planId for future flexibility
  required DateTime? expiresAt,
});
Future<SubscriptionTier> _getCachedTier();
Future<String?> _getCachedPlanId();
Future<DateTime?> _getCachedExpiry();
```

**What NOT to build:**
- ❌ Separate Repository layer
- ❌ PurchaseToken storage in database
- ❌ Complex subscription status objects
- ❌ Multiple storage layers

**Testing checkpoint:**
- [ ] Test tier persistence across app restarts
- [ ] Test expiry date handling
- [ ] Verify encrypted storage works
- [ ] Test offline behavior

## Phase 3: Purchase Flow (Days 3-4)

### 3.1 In-App Purchase Integration
**What to build:**
1. Add `in_app_purchase: ^3.2.0` to pubspec.yaml (ensures Play Billing v6+)
2. Configure products in SubscriptionManager:
   ```dart
   static const String subscriptionId = 'uplift_sub';
   static const String basicPlanId = 'basic_chat';
   static const String premiumPlanId = 'premium_voice_chat';
   ```
3. Implement purchase flow in SubscriptionManager
4. Add purchase listener for real-time updates

**Testing with Play Console:**
- [ ] Set up "test instrumented purchase" track
- [ ] Add QA device to test track
- [ ] Test purchase flow end-to-end
- [ ] Test upgrade from basic to premium
- [ ] Test downgrade from premium to basic
- [ ] Test refund flow

### 3.2 Minimal UI Changes
**What to build:**
1. Simple subscription screen with two options
2. Upgrade prompt when basic user taps voice
3. "Restore Purchases" button in settings
4. "Manage Subscription" button (deep link)

**What NOT to build:**
- ❌ Complex subscription management UI
- ❌ In-app cancellation flow
- ❌ Detailed subscription status displays
- ❌ Payment processing screens (use native IAP UI)

**Testing checkpoint:**
- [ ] Test complete purchase flow on device
- [ ] Verify tier updates immediately after purchase
- [ ] Test restore purchases functionality
- [ ] Ensure deep link to Play Store works

## Phase 4: Backend Webhook (Days 5-6)

### 4.1 Single RTDN Endpoint with Retry Logic
**What to build:**
```python
# Backend: POST /api/v1/subscriptions/google-webhook
async def handle_rtdn(notification: dict):
    try:
        # Verify notification with Google Play API
        # Update user's subscriptionTier and expiresAt
        return 200  # OK
    except Exception as e:
        # Log to dead-letter queue for retry
        await log_failed_rtdn(notification, str(e))
        return 200  # Still return 200 to prevent Google retry storm

# Simple dead-letter queue (Postgres table or SQS)
CREATE TABLE failed_rtdns (
    id SERIAL PRIMARY KEY,
    notification JSONB,
    error TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    retry_count INT DEFAULT 0
);
```

**Database changes:**
```sql
ALTER TABLE users ADD COLUMN subscription_tier VARCHAR(20) DEFAULT 'none';
ALTER TABLE users ADD COLUMN subscription_expires_at TIMESTAMP;
ALTER TABLE users ADD COLUMN subscription_plan_id VARCHAR(50); -- For future flexibility
```

**What NOT to build:**
- ❌ Complex sync services
- ❌ Fallback endpoints
- ❌ Purchase token storage
- ❌ Subscription history tracking

**Testing checkpoint:**
- [ ] Test webhook with Google's test notifications
- [ ] Verify database updates correctly
- [ ] Test renewal notifications
- [ ] Test cancellation notifications

## Phase 5: Remote Config Safety (Day 7)

### 5.1 Feature Flag Implementation (Safer Default)
**What to build:**
```dart
// Check remote config before any subscription logic
SubscriptionTier _fallbackTier() {
  final enableSubscriptions = remoteConfig.getBool('enable_subscription');
  if (!enableSubscriptions) {
    // Safer: Default to basic when flag is OFF
    // Prevents accidentally giving everyone premium
    return SubscriptionTier.basic;
  }
  return _cachedTier ?? SubscriptionTier.none;
}
```

**Testing checkpoint:**
- [ ] Test with flag enabled
- [ ] Test with flag disabled
- [ ] Verify instant rollback works
- [ ] Deploy to production with flag OFF initially

## Phase 6: Final Testing (Days 8-9)

### 6.1 End-to-End Testing Checklist
**On QA Device:**
- [ ] Fresh install → No subscription → Chat only
- [ ] Purchase basic → Chat works, voice blocked
- [ ] Upgrade to premium → Voice unlocked
- [ ] Downgrade to basic → Voice blocked again
- [ ] Cancel subscription → Tier persists until expiry
- [ ] After expiry → Reverts to no subscription
- [ ] Restore purchases → Correct tier restored
- [ ] Offline mode → Uses cached tier
- [ ] Auto-restore on cold start works (~5ms delay)

### 6.2 Edge Case Testing
**Critical scenarios to test:**
- [ ] Android 13 with Google Play disabled → BillingClient.isReady fallback works
- [ ] Purchase succeeds but acknowledge() fails → Retry on next launch
- [ ] RTDN arrives while backend offline → Queued in dead-letter table
- [ ] User refunds within 15 minutes → Google sends CANCEL, tier downgrades immediately
- [ ] Network failure during purchase → Clear error message, can retry
- [ ] Subscription expires during active session → Session continues, next session blocked

### 6.3 Production Readiness
**Before enabling in production:**
- [ ] RTDN webhook deployed with retry logic tested
- [ ] Dead-letter queue monitoring in place
- [ ] Remote config flag ready (default OFF)
- [ ] QA testing complete on multiple devices
- [ ] Rollback plan documented
- [ ] Support team briefed on subscription flows

## What We're NOT Building (Post-Launch)

Save these for after successful launch:
1. Sophisticated sync mechanisms
2. Detailed subscription analytics
3. Complex UI for subscription management
4. Grace period handling
5. Promotional offers
6. Family sharing
7. Pause/resume functionality
8. Detailed purchase history
9. **iOS Implementation** - Schedule the same lightweight approach with StoreKit 2 after Android GA

## Implementation Files Summary

**Total new files: 4-5**
1. `lib/services/subscription_manager.dart` - Core logic
2. `lib/models/subscription_tier.dart` - Simple enum
3. `lib/screens/subscription_screen.dart` - Purchase UI
4. `lib/widgets/upgrade_prompt.dart` - Upgrade nudges
5. Backend: One webhook endpoint

**Modified files: 3-4**
- `ChatScreen` - Hide voice button for basic tier
- `SharedPreferences` service - Add subscription caching
- Backend `User` model - Add two fields
- `main.dart` - Initialize SubscriptionManager

## Risk Mitigation

### Pre-Launch Safety
1. **Remote Config Flag**: Can disable entire feature instantly
2. **Test Track**: Full testing before production
3. **Minimal Changes**: Only touching UI visibility
4. **No Core Changes**: Voice/chat logic untouched
5. **Simple Rollback**: Just flip the flag

### Launch Day Plan
1. Enable with 1% rollout via remote config
2. Monitor for 2 hours
3. Increase to 10% if stable
4. Full rollout after 24 hours of stability

## Success Metrics

**MVP Success = These work correctly:**
- Free users can only use chat
- Basic tier users can only use chat
- Premium tier users can use voice + chat
- Purchases complete successfully
- Tier persists across app restarts
- RTDN updates backend correctly

## Timeline Summary

**Total: 8-9 days** (vs 14 days original)
- Day 1: SubscriptionManager + basic gating
- Day 2: Data model + caching (with planId for flexibility)
- Days 3-4: Purchase flow + minimal UI (Play Billing v6+)
- Days 5-6: Backend webhook with retry logic
- Day 7: Remote config safety (safer Basic default)
- Days 8-9: End-to-end + edge case testing

**Rollback time: <1 minute** (via remote config)

## Key Technical Requirements

1. **Dependencies**:
   - `in_app_purchase: ^3.2.0` or higher (Play Billing v6+ compliance)
   - Existing remote config setup

2. **Critical Implementation Details**:
   - Cache planId alongside tier for future flexibility
   - Auto-restore on cold start (queryPurchasesAsync)
   - RTDN retry logic with dead-letter queue
   - Default to Basic tier when feature flag is OFF
   - Acknowledge purchases properly to avoid Google penalties

3. **Testing Requirements**:
   - Use Play Console's "test instrumented purchase" track
   - Test all edge cases before production
   - Monitor dead-letter queue for failed RTDNs

This lightweight approach gets you to market quickly with minimal risk, and provides a solid foundation for post-launch enhancements.