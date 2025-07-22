# Google Play Console Setup Guide

This guide helps you configure subscriptions in Google Play Console for the AI Therapist app.

## Prerequisites

1. Google Play Developer account ($25 one-time fee)
2. App uploaded to Play Console (at least internal testing track)
3. Merchant account linked for payments

## Step 1: Create Subscription Products

1. Sign in to [Google Play Console](https://play.google.com/console)
2. Select your app
3. Navigate to **Monetization** → **Subscriptions**
4. Click **Create subscription**

### Basic Plan Subscription
- **Product ID**: `basic_chat`
- **Name**: Basic Chat Therapy
- **Description**: Unlimited text-based therapy sessions with our AI therapist
- **Billing period**: Monthly
- **Default price**: $1.00 USD
- **Free trial**: 7 days (recommended)
- **Grace period**: 3 days
- **Status**: Active

### Premium Plan Subscription
- **Product ID**: `premium_voice_chat`
- **Name**: Premium Voice & Chat Therapy
- **Description**: Full access to voice and chat therapy sessions with advanced features
- **Billing period**: Monthly
- **Default price**: $10.00 USD
- **Free trial**: 7 days (recommended)
- **Grace period**: 3 days
- **Status**: Active

## Step 2: Configure Base Plans and Offers

For each subscription:

1. Click on the subscription
2. Under **Base plans and offers**, click **Add base plan**
3. Configure:
   - **Base plan ID**: `monthly` 
   - **Renewal type**: Auto-renewing
   - **Billing period**: 1 month
   - **Price**: Set your price for each region

4. Add a free trial offer:
   - Click **Add offer** under the base plan
   - **Offer ID**: `freetrial`
   - **Eligibility**: New customers
   - **Offer phases**:
     - Phase 1: Free trial, 7 days, $0.00
     - Phase 2: Regular price (auto-transitions)

## Step 3: Testing Configuration

1. Go to **Settings** → **License testing**
2. Add test email addresses:
   - Your personal Gmail
   - Team member emails
   - Test accounts

3. Set **License test response**: "Licensed"

## Step 4: App Configuration

1. Ensure `android/app/build.gradle` has correct package name:
```gradle
applicationId "com.uplift.ai_therapist_app"
```

2. Version code must be incremented for each upload:
```gradle
versionCode 2  // Increment this
versionName "1.0.1"
```

## Step 5: Required Permissions

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="com.android.vending.BILLING" />
<uses-permission android:name="android.permission.INTERNET" />
```

## Step 6: Upload and Testing

1. Build APK for testing:
```bash
# Use the provided script
./scripts/build_for_testing.sh

# Or manually:
flutter build apk --debug  # Debug APK works for internal testing
```

2. **Upload to Internal testing**:
   - Go to Release → Testing → Internal testing
   - Create new release
   - Upload APK from `build/app/outputs/flutter-apk/`
   - Add release notes
   - Review and rollout

3. **Set up testers**:
   - Add testers via email or create shareable link
   - Testers install via Play Store internal testing link

4. **Wait 2-4 hours** for subscription products to propagate

5. **Test flow**:
   - Install app from internal testing link
   - Navigate to subscription screen
   - Select a plan (should show "Start Free Trial")
   - Complete Google Play purchase flow

## Step 7: Verify Implementation

The app's subscription flow:
1. User taps subscription option
2. Google Play dialog shows with 7-day trial highlighted
3. User confirms (no charge for 7 days)
4. After trial, automatic monthly billing begins
5. User can cancel anytime in Play Store subscriptions

## Common Issues

### "Item unavailable" error
- Wait 24 hours after creating products
- Ensure app is signed with release key
- Check package name matches exactly
- Verify products are "Active" status

### Subscription not showing
- Clear Google Play Store cache
- Ensure test account is licensed tester
- Check product IDs match exactly in code

### Testing without charges
- Use license tester accounts
- Test cards in Play Console test settings
- Cancel before trial ends to avoid charges

## Backend Integration (Optional)

For real-time subscription status:
1. Set up Google Play Developer API
2. Configure Pub/Sub for real-time notifications
3. Implement webhook endpoint for status updates

Current implementation polls subscription status on app launch, which is sufficient for most use cases.