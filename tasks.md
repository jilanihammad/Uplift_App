# Backend Testing & Streaming Implementation Checklist

## 1. Backend Setup
- [x] Pull the latest backend code from GitHub
- [x] Set up local environment (install dependencies, configure .env)

## 2. Baseline Endpoint Testing
- [x] Test chat completion endpoint (non-streaming)
- [x] Test TTS (Text-to-Speech) endpoint (JSON)
- [x] Test transcription endpoint (base64 JSON)
- [x] Test transcription endpoint (file upload, if available)
- [x] Test any other relevant endpoints

## 3. Optional: Add/Enable File Upload Endpoints
- [x] Add/enable file upload endpoint for transcription (if not present)

## 4. Implement Streaming Audio Changes (WebSocket)
- [x] Design WebSocket message format for chat completion
- [x] Implement backend WebSocket streaming logic for /ws/chat using Groq's streaming API
- [x] Test with wscat to confirm incremental JSON messages
- [x] Document the message format for streaming chat completion
- [x] Update Flutter frontend to handle streamed JSON messages
- [x] Design WebSocket message format for TTS
- [x] Implement /ws/tts endpoint (WebSocket TTS streaming)
- [x] Document message formats for Flutter integration

## 5. Local Streaming Endpoint Testing (WebSocket)
- [x] Test WebSocket chat streaming endpoint
- [x] Test WebSocket TTS streaming endpoint

## 6. Deploy to Staging/Production
- [x] Deploy updated backend to cloud environment
- [x] Update environment variables/configs as needed

## 7. Post-Deployment Testing
- [x] Test all endpoints in deployed environment (non-streaming)
- [x] Test all streaming endpoints in deployed environment
- [x] Document any issues or follow-ups needed

## 8. Regression & Final Review
- [x] Confirm all endpoints (old and new) work as expected
- [x] Review logs for errors or warnings
- [x] Document any issues or follow-ups needed

---

## Flutter Integration: Streaming Chat Completion
- [x] Add WebSocket client logic to Flutter app for /ws/chat
- [x] Send initial JSON message with message, history, and session_id
- [x] Parse and handle incoming 'chunk' messages (append to chat UI)
- [x] Handle 'done' and 'error' message types
- [x] Display streamed response in real time in the chat UI
- [x] Handle reconnection and error states gracefully
- [x] Test on device (SM S938U1) for real-time streaming experience

---

## Flutter Integration: BLoC/WebSocket Streaming Chat (Detailed)
- [x] Refactor chat logic into a ChatBloc to manage WebSocket stream and chat state
- [x] Replace mock GroqService with actual WebSocket service (connects to backend /ws/chat)
- [x] Implement a ChatMessage model (with sender, timestamp, content, etc.)
- [x] Update ChatBloc to use ChatMessage model instead of String
- [x] Pass real sessionId from session management logic
- [x] Add robust error handling and reconnection logic in ChatBloc
- [x] Integrate ChatBloc with chat screen using BlocProvider and BlocBuilder
- [x] Update chat UI to display sender, timestamps, and streaming indicators
- [x] Add text input and send button for user messages
- [x] Test on device (SM S938U1) for real-time streaming, reconnection, and error handling
- [x] Iterate and refine based on user feedback and production testing

---

## WebSocket /ws/chat Message Format
- [x] Document the message format for streaming chat completion (already designed, but needs documentation)

---

## Future Improvement
- [ ] After all core features are implemented and tested, explore upgrading session management from in-memory to a persistent store (e.g., Redis or database) for production reliability and scalability. 

---

**Note:** If any chat streaming step is still pending, please specify and we can revisit. Otherwise, all core streaming features (TTS and chat) are now marked as complete. 