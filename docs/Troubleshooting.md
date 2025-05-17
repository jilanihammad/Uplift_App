# Troubleshooting Guide

This guide covers common issues and solutions for both the backend and frontend of the AI Therapist App.

---

## Backend Issues

### 403 Forbidden
- **Cause:** Invalid or missing API key, endpoint permissions, or Cloud Run/IAM misconfiguration.
- **Solution:**
  - Check your `.env` for a valid `OPENAI_API_KEY`.
  - Ensure your Cloud Run service allows unauthenticated access (if needed).
  - Review backend logs for permission errors.

### WebSocket Not Connecting
- **Cause:** Wrong URL, backend not running, firewall, or HTTPS/WSS mismatch.
- **Solution:**
  - Double-check the WebSocket URL (should be `/ws/chat` or `/voice/ws/tts`).
  - Ensure the backend is running and accessible from your device.
  - Use `wscat` to test: `wscat -c ws://localhost:8000/ws/chat`
  - For production, use `wss://` and ensure SSL is configured.

### Audio Not Streaming
- **Cause:** OpenAI API key issue, backend error, or unsupported audio format.
- **Solution:**
  - Check backend logs for errors from the TTS endpoint.
  - Ensure `response_format` is set to `opus` or fallback to `mp3`.
  - Test with a simple TTS request using curl or wscat.

### Timeouts
- **Cause:** Slow network, backend processing delays, or server timeout settings.
- **Solution:**
  - Increase server timeout settings if needed.
  - Optimize backend code for faster response.

---

## Frontend Issues

### WebSocket Not Connecting
- **Cause:** Wrong backend URL, network/firewall, or backend not running.
- **Solution:**
  - Update the backend URL in `lib/config/app_config.dart`.
  - Test backend connectivity with curl or wscat.

### Audio Not Playing
- **Cause:** Permissions, device volume, or audio file issues.
- **Solution:**
  - Grant microphone and audio permissions.
  - Check device volume and mute settings.
  - Review logs for playback errors.

### App Crashes on Startup
- **Cause:** Flutter setup issues, missing dependencies, or misconfiguration.
- **Solution:**
  - Run `flutter doctor` and resolve any issues.
  - Ensure all dependencies are installed with `flutter pub get`.

### TTS Not Streaming
- **Cause:** Backend endpoint unreachable, API key issue, or network problem.
- **Solution:**
  - Check backend logs and endpoint status.
  - Verify API key and network connectivity.

---

## Debugging Tips

- **Backend logs:** Check terminal or cloud logs for errors.
- **Frontend logs:** Use `flutter run` for real-time logs.
- **Test endpoints:** Use `curl` or `wscat` to verify backend endpoints.
- **Check .env:** Ensure all required environment variables are set.

---

## FAQ / Common Issues

- **Why isn't the WebSocket connecting?**
  - Check backend URL, server status, and network.
- **How do I get an OpenAI API key?**
  - Sign up at https://platform.openai.com/ and create an API key.
- **Audio isn't playing on my device.**
  - Ensure permissions are granted and device volume is up.
- **How do I debug a backend error?**
  - Check logs, test with curl/wscat, and verify API keys.

---

## Getting Help

- **Report bugs:** Open an issue on GitHub.
- **Community:** Join the project's Discord/Slack (if available).
- **Contribute:** See [CONTRIBUTING.md](../CONTRIBUTING.md) 