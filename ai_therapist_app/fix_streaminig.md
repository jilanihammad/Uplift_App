 Updated Comprehensive Fix Plan for Maya's Response Issues                             │
     │                                                                                       │
     │ 1. Fix BLoC Async/Emit Misuse (CRITICAL - Causes App Crash)                           │
     │                                                                                       │
     │ File: lib/blocs/voice_session_bloc.dart (lines 646-654)                               │
     │ - Problem: emit() is called inside Future.delayed callback after event handler        │
     │ completes                                                                             │
     │ - Fix: Make the event handler async and await the delay                               │
     │ Future<void> _onTtsStateChanged(TtsStateChanged event, Emitter<VoiceSessionState>     │
     │ emit) async {                                                                         │
     │   debugPrint('[VoiceSessionBloc] TTS state changed: ${event.isSpeaking}');            │
     │                                                                                       │
     │   final bool wasSpeaking = state.isAiSpeaking;                                        │
     │   emit(state.copyWith(isAiSpeaking: event.isSpeaking));                               │
     │                                                                                       │
     │   if (wasSpeaking && !event.isSpeaking && !state.isInitialGreetingPlayed &&           │
     │ state.isVoiceMode) {                                                                  │
     │     emit(state.copyWith(isInitialGreetingPlayed: true));                              │
     │     await Future.delayed(const Duration(milliseconds: 125));                          │
     │     if (state.isVoiceMode && !state.isAutoListeningEnabled && !state.isRecording) {   │
     │       add(const EnableAutoMode());                                                    │
     │     }                                                                                 │
     │   }                                                                                   │
     │ }                                                                                     │
     │                                                                                       │
     │ 2. Fix VAD Resume Timing - Tie to TTS "done" Signal                                   │
     │                                                                                       │
     │ Files: lib/services/tts_service.dart and lib/services/audio_generator.dart            │
     │                                                                                       │
     │ Current Issue: VAD resumes when AudioPlayer finishes playing chunks, not when TTS     │
     │ stream completes                                                                      │
     │                                                                                       │
     │ Fix in tts_service.dart:                                                              │
     │ - Modify the WebSocket "done" handler to trigger VAD resume                           │
     │ - Remove VAD resume from audio playback completion                                    │
     │ } else if (data['type'] == 'done') {                                                  │
     │   // ... existing audio processing code ...                                           │
     │                                                                                       │
     │   // Only call onDone AFTER audio playback completes                                  │
     │   await _audioPlayerManager.playAudio(filePath!);                                     │
     │                                                                                       │
     │   onDone?.call();  // This should trigger VAD resume                                  │
     │                                                                                       │
     │   if (kDebugMode) {                                                                   │
     │     print('[TTSService] TTS stream done, audio played successfully');                 │
     │   }                                                                                   │
     │                                                                                       │
     │   finishTTS();                                                                        │
     │ }                                                                                     │
     │                                                                                       │
     │ Fix in audio_generator.dart (processAIResponseWithStreamingTTS):                      │
     │ await _ttsService.streamAndPlayTTSChunked(                                            │
     │   textStream,                                                                         │
     │   sessionId: sessionId,                                                               │
     │   onDone: () async {                                                                  │
     │     log.i('🎵 TTS chunked streaming completed - resuming VAD');                       │
     │     // Resume VAD only after receiving "done" from backend                            │
     │     await _vadResumeCallback?.call();                                                 │
     │     onTTSComplete();                                                                  │
     │   },                                                                                  │
     │   // ... rest of parameters                                                           │
     │ );                                                                                    │
     │                                                                                       │
     │ 3. Fix TTS Buffering Implementation                                                   │
     │                                                                                       │
     │ Ensure buffering is actually used for all TTS operations                              │
     │                                                                                       │
     │ Check these locations:                                                                │
     │ 1. Verify processAIResponseWithStreamingTTS uses streamAndPlayTTSChunked (it does ✓)  │
     │ 2. Ensure text chunks are properly accumulated before sending to TTS                  │
     │ 3. Verify buffer thresholds are working (50-200 chars)                                │
     │                                                                                       │
     │ Debug addition to see if buffering is working:                                        │
     │ // In tts_service.dart _processTextWithBuffering                                      │
     │ if (kDebugMode) {                                                                     │
     │   print('[TTSService] Buffer[$bufferId] received ${text.length} chars, total buffer:  │
     │ ${currentBufferContent.length} chars');                                               │
     │   print('[TTSService] Should process: ${_shouldProcessBuffer(currentBufferContent)}');│
     │ }                                                                                     │
     │                                                                                       │
     │ 4. Fix Timer/VAD Race Condition                                                       │
     │                                                                                       │
     │ File: lib/services/auto_listening_coordinator.dart                                    │
     │                                                                                       │
     │ Add state guards and debouncing:                                                      │
     │ // Add instance variables                                                             │
     │ bool _isStoppingRecording = false;                                                    │
     │ DateTime? _lastSpeechEndTime;                                                         │
     │ static const _speechEndDebounceMs = 300;                                              │
     │                                                                                       │
     │ void _startSpeechEndTimer() {                                                         │
     │   // Guard against invalid states                                                     │
     │   if (_isStoppingRecording || currentState != AutoListeningState.userSpeaking) {      │
     │     debugPrint('[AutoListeningCoordinator] Skipping timer - stopping:                 │
     │ $_isStoppingRecording, state: $currentState');                                        │
     │     return;                                                                           │
     │   }                                                                                   │
     │                                                                                       │
     │   // Debounce rapid speech end events                                                 │
     │   final now = DateTime.now();                                                         │
     │   if (_lastSpeechEndTime != null &&                                                   │
     │       now.difference(_lastSpeechEndTime!).inMilliseconds < _speechEndDebounceMs) {    │
     │     debugPrint('[AutoListeningCoordinator] Debouncing speech end event');             │
     │     return;                                                                           │
     │   }                                                                                   │
     │   _lastSpeechEndTime = now;                                                           │
     │                                                                                       │
     │   _cancelSpeechEndTimer();                                                            │
     │   // ... rest of timer logic                                                          │
     │ }                                                                                     │
     │                                                                                       │
     │ Future<void> _stopRecording() async {                                                 │
     │   if (_isStoppingRecording) return;                                                   │
     │   _isStoppingRecording = true;                                                        │
     │                                                                                       │
     │   try {                                                                               │
     │     // ... existing stop recording logic ...                                          │
     │   } finally {                                                                         │
     │     _isStoppingRecording = false;                                                     │
     │   }                                                                                   │
     │ }                                                                                     │
     │                                                                                       │
     │ 5. Remove VAD Resume from Audio Playback                                              │
     │                                                                                       │
     │ Files: lib/services/audio_player_manager.dart, lib/services/tts_service.dart          │
     │                                                                                       │
     │ Ensure VAD resume is NOT triggered by:                                                │
     │ - Individual audio chunk playback completion                                          │
     │ - AudioPlayerManager state changes                                                    │
     │ - Any path except the TTS WebSocket "done" event                                      │
     │                                                                                       │
     │ 6. Add Comprehensive Logging                                                          │
     │                                                                                       │
     │ Add debug logs to track the full flow:                                                │
     │ // When TTS starts                                                                    │
     │ print('[TTS-VAD] TTS started, pausing VAD');                                          │
     │                                                                                       │
     │ // When chunks arrive                                                                 │
     │ print('[TTS-VAD] TTS chunk ${chunkNumber} received');                                 │
     │                                                                                       │
     │ // When audio plays                                                                   │
     │ print('[TTS-VAD] Playing audio chunk ${chunkNumber}');                                │
     │                                                                                       │
     │ // When backend sends done                                                            │
     │ print('[TTS-VAD] Backend sent "done" signal');                                        │
     │                                                                                       │
     │ // When VAD resumes                                                                   │
     │ print('[TTS-VAD] Resuming VAD after TTS complete');                                   │
     │                                                                                       │
     │ Implementation Order:                                                                 │
     │                                                                                       │
     │ 1. First: Fix BLoC emit issue (prevents crashes) - 5 min                              │
     │ 2. Second: Fix VAD resume timing to use "done" signal - 15 min                        │
     │ 3. Third: Remove VAD resume from audio playback paths - 10 min                        │
     │ 4. Fourth: Fix timer race conditions with guards - 10 min                             │
     │ 5. Fifth: Verify TTS buffering is working - 10 min                                    │
     │ 6. Sixth: Add comprehensive logging and test - 10 min                                 │
     │                                                                                       │
     │ Expected Results:                                                                     │
     │                                                                                       │
     │ - ✅ No more app crashes from BLoC assertion errors                                    │
     │ - ✅ VAD only resumes after Maya completely finishes speaking (backend "done" signal)  │
     │ - ✅ No more Maya self-detection issues                                                │
     │ - ✅ Stable state transitions without race conditions                                  │
     │ - ✅ TTS buffering reduces API calls and improves speech quality                       │
     │ - ✅ Clear logging to debug any remaining issues                                       │
     │                                                                                       │
     │ Key Insight:                                                                          │
     │                                                                                       │
     │ The most important fix is ensuring VAD resumption is tied to the TTS WebSocket "done" │
     │ message from the backend, not to local audio playback events. This guarantees VAD only│
     │  activates after Maya has completely finished her response.  