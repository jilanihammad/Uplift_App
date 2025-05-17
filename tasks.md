# Backend Testing & Streaming Implementation Checklist

## 1. Backend Setup
- [x] Pull the latest backend code from GitHub
- [x] Set up local environment (install dependencies, configure .env)

## 2. Baseline Endpoint Testing
- [x] Test chat completion endpoint (non-streaming)
- [x] Test TTS (Text-to-Speech) endpoint (JSON)
- [x] Test transcription endpoint (base64 JSON)
- [x] Test transcription endpoint (file upload, if available)
- [ ] Test any other relevant endpoints

## 3. Optional: Add/Enable File Upload Endpoints
- [x] Add/enable file upload endpoint for transcription (if not present)

## 4. Implement Streaming Audio Changes (WebSocket)
- [x] Design WebSocket message format for chat completion
- [x] Implement backend WebSocket streaming logic for /ws/chat using Groq's streaming API
- [ ] Test with wscat to confirm incremental JSON messages
- [ ] Document the message format for streaming chat completion
- [ ] Update Flutter frontend to handle streamed JSON messages
- [ ] Design WebSocket message format for TTS
- [ ] Implement /ws/tts endpoint (WebSocket TTS streaming)
- [ ] Document message formats for Flutter integration

## 5. Local Streaming Endpoint Testing (WebSocket)
- [ ] Test WebSocket chat streaming endpoint
- [ ] Test WebSocket TTS streaming endpoint

## 6. Deploy to Staging/Production
- [ ] Deploy updated backend to cloud environment
- [ ] Update environment variables/configs as needed

## 7. Post-Deployment Testing
- [ ] Test all endpoints in deployed environment (non-streaming)
- [ ] Test all streaming endpoints in deployed environment

## 8. Regression & Final Review
- [ ] Confirm all endpoints (old and new) work as expected
- [ ] Review logs for errors or warnings
- [ ] Document any issues or follow-ups needed

---

## Flutter Integration: Streaming Chat Completion
- [ ] Add WebSocket client logic to Flutter app for /ws/chat
- [ ] Send initial JSON message with message, history, and session_id
- [ ] Parse and handle incoming 'chunk' messages (append to chat UI)
- [ ] Handle 'done' and 'error' message types
- [ ] Display streamed response in real time in the chat UI
- [ ] Handle reconnection and error states gracefully
- [ ] Test on device (SM S938U1) for real-time streaming experience

---

## Flutter Integration: BLoC/WebSocket Streaming Chat (Detailed)
- [x] Refactor chat logic into a ChatBloc to manage WebSocket stream and chat state
- [x] Replace mock GroqService with actual WebSocket service (connects to backend /ws/chat)
- [ ] Implement a ChatMessage model (with sender, timestamp, content, etc.)
- [ ] Update ChatBloc to use ChatMessage model instead of String
- [ ] Pass real sessionId from session management logic
- [ ] Add robust error handling and reconnection logic in ChatBloc
- [ ] Integrate ChatBloc with chat screen using BlocProvider and BlocBuilder
- [ ] Update chat UI to display sender, timestamps, and streaming indicators
- [ ] Add text input and send button for user messages
- [ ] Test on device (SM S938U1) for real-time streaming, reconnection, and error handling
- [ ] Iterate and refine based on user feedback and production testing

---

## WebSocket /ws/chat Message Format

### Input (from client):
```
{
  "message": "Hello, Maya!",
  "history": [],
  "session_id": "abc123"   // Optional, but recommended
}
```
- `session_id`: Associates the message with a specific conversation or user session.

### Output (from server, streamed):
- Each chunk:
```
{
  "type": "chunk",
  "content": "Hi there",
  "sequence": 1,           // Sequence number (starts at 1)
  "timestamp": "2024-06-09T12:34:56.789Z"  // ISO 8601
}
```
- When complete:
```
{
  "type": "done",
  "sequence": 2,           // Final sequence number
  "timestamp": "2024-06-09T12:34:57.000Z"
}
```
- On error:
```
{
  "type": "error",
  "detail": "Error message",
  "timestamp": "2024-06-09T12:34:57.123Z"
}
```
- `sequence`: Ensures correct order of streamed chunks.
- `timestamp`: When the message was sent (ISO 8601 format).

*Check off each box as you complete the step to track progress and ensure nothing is missed!*

---

## Future Improvement
- [ ] After all core features are implemented and tested, explore upgrading session management from in-memory to a persistent store (e.g., Redis or database) for production reliability and scalability. 