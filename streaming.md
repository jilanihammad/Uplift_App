Ticket: “Refactor to True Token-Level TTS Streaming”
Field	Content
Why (problem)	Current “pseudo-streaming” waits for the full model reply, then fakes chunks. Users experience a 2-5 s silent gap and we waste latency/bandwidth.
Goal (definition of done)	• Audio for the first token plays < 400 ms after backend begins generating.
• No UI “TTS streaming” state without audio on the wire.
• End-to-end failure rate ≤ 1 % across 100 conversations.
Scope	Both backend and mobile client; no UI redesign.
Out of scope	Voice activity detection (VAD) algorithm changes, transcription pipeline, multilingual voice selection.
Milestones & Tasks	

Backend ✨

Add WebSocket / HTTP-2 SSE endpoint POST /stream/ai-response that returns JSON events:

json
Copy
Edit
{ "type": "token", "text": "Hello" }  
{ "type": "sentence_end" }  
{ "type": "eof" }
› If infra team prefers, GRPC streaming is acceptable.

Emit tokens immediately as the model produces them (max 50 ms flush interval).

Preserve old REST endpoint for fallback until adoption is ≥ 95 %.

Acceptance test: latency (ServerTime[first_token] – request) < 120 ms in staging.

Mobile client (Flutter) 🛰️

Transport layer

Add StreamingApiClient using web_socket_channel or grpc.

Automatic reconnect & back-pressure (write flow-control credits every 1 s).

Streaming pipeline refactor

Replace _processUserMessageWithRealTimeStreaming() with a coroutine:

dart
Copy
Edit
await for (final chunk in stream) {
  buffer.add(chunk.text);
  if (isSentenceComplete(buffer)) tts.play(buffer.flush());
}
Start TTS after first sentence OR configurable token threshold (e.g., 30 chars) to maintain natural prosody.

State handling

VoiceSessionBloc gets new events: TtsPreparing, TtsPlaying.

UI shows “thinking…” until TtsPlaying.

Error & timeout guards

If no token event within 500 ms of connection → fallback to REST path.

If connection drops mid-stream, attempt resume (idempotent conversation_id).

Instrumentation

Emit tts_first_audio_latency_ms, stream_retries, tokens_per_second.

Audio layer 🎧

Change AudioGenerator to accept incremental text (addText(String t)), queue in synchronized buffer, and stream to TTS engine without stopping playback.

Maintain small 5-sentence ring buffer for graceful cancel/skip.

QA & rollout 🚀

Internal dogfood with staged rollout flag enableTrueStreamingTTS.

Compare metrics vs. control (REST) for 1 week.

Flip flag to 100 % when:

Mean first-audio latency ≤ 600 ms on 4G

Crash-free TTS sessions ≥ 99 %

User-reported “awkward silence” tickets decrease by ≥ 75 %.

Cleanup 🧹

Remove fake chunk-splitting code paths.

Deprecate old TtsStatus.streaming semantics; migrate to preparing + playing.

| Risks / Mitigations |
|—|—|
| Mobile data overages due to continuous socket | Use protobuf framing, gzip WebSocket compression. |
| Token spam stalls TTS prosody | Buffer until sentence ends or punctuation heuristic. |
| Backend memory pressure from many open streams | Set 2-minute idle timeout; reuse model sessions. |

| Success metrics |
|—|—|
| P50 first-audio latency | ⬇ from ~2500 ms → ≤ 600 ms |
| P95 end-to-end latency (user speak → AI finish) | ⬇ ≥ 20 % |
| User CSAT for “response speed” | +1 pt within 30 days |