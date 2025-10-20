# Voice Session Testing Checklist

## Test Environment Setup
- [ ] Connect phone via USB debugging or use wireless debugging
- [ ] Run `flutter run` with device connected
- [ ] Open terminal/console to monitor debug logs
- [ ] Clear any previous app data/cache if needed

## Key Areas to Monitor in Logs

### 1. Session Lifecycle
Look for these log patterns:
```
[VoiceService] Beginning new session...
[VoiceService] Shutdown initiated
[VoiceService] Shutdown completed successfully
[AutoListeningCoordinator] Session marked inactive
```

### 2. Audio State Changes
Monitor these transitions:
```
[VoiceService] TTS Speaking State: true/false
[AutoListeningCoordinator] State transition: idle → listening → speechDetected → recording
[VoiceSessionBloc] TTS state changed: true/false
```

### 3. Error Patterns to Watch For
```
Null check operator used on a null value
Access denied for recorder
Stream already closed
Cannot add events after close
```

## Test Scenarios

### Test 1: Basic Session Flow
1. Start app and select mood
2. Wait for welcome message to complete
3. Verify Maya starts listening automatically
4. Speak a message
5. Verify Maya responds with TTS
6. Check that Maya resumes listening after speaking

### Test 2: End Session During Various States
1. **During Maya's TTS playback**: Press "End Session"
   - Verify TTS stops immediately
   - Verify no further listening occurs
   
2. **While recording user speech**: Press "End Session"
   - Verify recording stops
   - Verify no transcription attempts
   
3. **During idle listening**: Press "End Session"
   - Verify VAD stops cleanly

### Test 3: Rapid Session Restart
1. Start a session and interact briefly
2. Press "End Session"
3. **Immediately** select a new mood to start new session
4. Monitor for:
   - Fresh session ID in logs
   - Clean VAD initialization
   - No "stuck listening" state
   - Welcome message plays correctly
   - Auto-listening enables after welcome

### Test 4: TTS Latency Measurement
1. Send a text message in chat mode
2. Switch to voice mode
3. Speak a message
4. Time from end of speech to start of Maya's response
5. Target: < 3 seconds total latency

### Test 5: Session State Isolation
1. Start session 1, have a conversation
2. End session
3. Start session 2
4. Verify:
   - No context bleed from session 1
   - Fresh coordinator instance
   - New session ID
   - Clean state initialization

### Test 6: Error Recovery
1. Test network disconnection during session
2. Test switching apps during recording
3. Test phone call interruption
4. Verify graceful recovery or error messages

## Performance Metrics to Track

### TTS Latency Breakdown
- Speech end detection: ~1.5s (debounce timer)
- Audio upload & transcription: ~0.5-1s
- AI response generation: ~1-2s
- TTS generation & playback start: ~0.5-1s
- **Total target**: 3.5-5.5s

### Memory & Resource Usage
- Monitor for memory leaks during session transitions
- Check that audio files are cleaned up
- Verify disposed managers don't retain resources

## Debug Commands to Run

```bash
# Watch for specific patterns
adb logcat | grep -E "(VoiceService|AutoListening|VoiceSessionBloc|Error|null)"

# Monitor memory usage
adb shell dumpsys meminfo com.yourapp.package

# Check for file cleanup
adb shell ls /data/data/com.yourapp.package/cache/
```

## Expected Behavior Checklist

### On Session Start
- [ ] Fresh session ID generated
- [ ] Welcome message plays
- [ ] Auto-listening enables after welcome
- [ ] No errors in logs

### During Conversation
- [ ] Smooth state transitions
- [ ] TTS plays without cutting off
- [ ] VAD detects speech reliably
- [ ] No duplicate recordings

### On Session End
- [ ] All audio stops immediately
- [ ] No further listening/recording
- [ ] Clean shutdown logs
- [ ] No null-check errors

### On New Session After End
- [ ] Fresh instances created
- [ ] No state carried over
- [ ] Welcome message plays
- [ ] Normal operation resumes

### Release Regression Add-ons
- [ ] Remote kill switch toggled off (via Remote Config or debug override) and streaming path confirms fallback to full-buffer mode
- [ ] Remote kill switch toggled back on and streaming resumes (watch `[TTS] Using STREAMING path` logs)
- [ ] Settings → Privacy & Security entries open AI disclosure dialog, crisis resources sheet, and account deletion link
- [ ] Account deletion dialog surfaces warning before launching external browser
- [ ] Privacy Policy/Terms links open in external browser without crashing

## Common Issues & Solutions

### Issue: "Access denied for recorder"
- Check SharedRecorderManager ownership logs
- Verify coordinatorId is unique per session

### Issue: Null check operator crash
- Check shutdown timing in logs
- Verify capture-before-nulling pattern

### Issue: Maya keeps listening after end
- Check session guards in timer callbacks
- Verify _sessionActive = false propagation

### Issue: Welcome message cuts off
- Check TTS state management
- Verify no premature VAD activation
