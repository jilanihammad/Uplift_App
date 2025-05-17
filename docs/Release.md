# Release & Monitoring Guide

This guide covers how to deploy, monitor, and maintain the AI Therapist App in production.

---

## Production Deployment

### Backend (Cloud Run or similar)
1. Build and push your Docker image (if using Cloud Run):
   ```bash
   gcloud builds submit --tag gcr.io/your-project/ai-therapist-backend
   gcloud run deploy ai-therapist-backend --image gcr.io/your-project/ai-therapist-backend --platform managed --region us-central1 --allow-unauthenticated
   ```
2. Set environment variables (API keys, etc.) in your cloud provider's dashboard.
3. Ensure HTTPS/WSS is enabled for all endpoints.
4. Update DNS or app config with the new backend URL.

### Frontend (App Store/Play Store or Web)
1. Build the Flutter app for release:
   ```bash
   flutter build apk   # Android
   flutter build ios   # iOS
   flutter build web   # Web (optional)
   ```
2. Follow platform-specific steps to publish to Google Play, App Store, or web hosting.
3. Update backend URL in app config if needed.

---

## Environment Variables (Production)

- **Backend:**
  - `OPENAI_API_KEY=your-prod-key`
  - `PORT=8080` (or as required by your platform)
  - Any other provider keys
- **Frontend:**
  - Set backend URL in `lib/config/app_config.dart` or via build-time env vars

---

## Post-Deployment Testing Checklist

- [ ] Test chat and TTS endpoints (REST and WebSocket)
- [ ] Test on real devices (Android/iOS)
- [ ] Verify audio streaming and chat streaming work in production
- [ ] Check logs for errors or warnings
- [ ] Confirm all environment variables are set

---

## Monitoring & Logging

- **Backend:**
  - Use Google Cloud Run logs, Stackdriver, or your provider's logging tools
  - Set up alerts for errors or high latency
- **Frontend:**
  - Integrate with Sentry, Firebase Crashlytics, or similar for error reporting
- **User Feedback:**
  - Add in-app feedback or link to GitHub issues

---

## Rollback & Updates

- **Backend:**
  - Use your cloud provider's revision history to roll back to a previous version
  - Always test new deployments in staging before production
- **Frontend:**
  - Publish hotfixes or updates via the app store or web host
  - Notify users of major changes

---

## Collecting User Feedback

- Add a feedback form or link in the app
- Monitor app store reviews and GitHub issues
- Respond to user reports promptly

---

## Release Notes / Versioning

### v1.0.0
- Initial public release: real-time chat and TTS streaming, device support, robust error handling

### v1.1.0
- (Add new features, bug fixes, or improvements here)

---

## Further Reading
- [Backend Setup & API](Backend.md)
- [Frontend Setup & Integration](Frontend.md)
- [Troubleshooting](Troubleshooting.md) 