# Quick Testing Guide

## Installation
1. Transfer the APK to your phone:
   ```bash
   adb install build/app/outputs/flutter-apk/app-debug.apk
   ```
   Or manually copy the APK and install it.

2. To monitor logs while testing:
   ```bash
   adb logcat | grep -E "(VoiceService|AutoListening|VoiceSessionBloc|Error|null|Shut|Session|VAD|TTS)"
   ```

## Critical Tests to Run

### 1. Session End/Restart Test (PRIORITY)
1. Start a session
2. Have a brief conversation
3. Press "End Session"
4. **Immediately** select new mood
5. Check:
   - ✓ Maya stops listening when ending
   - ✓ Fresh session starts cleanly
   - ✓ No "stuck listening" state
   - ✓ Welcome message plays

### 2. Audio State Changes
Watch the logs for these key transitions:
```
[VoiceService] Beginning new session...
[VoiceService] TTS Speaking State: true → false
[AutoListeningCoordinator] State: idle → listening
[VoiceService] Shutdown completed successfully
```

### 3. TTS Latency Check
- Time from speech end to Maya's response start
- Target: < 3-4 seconds

### 4. Error Monitoring
Watch for these errors:
- ❌ "Null check operator used on a null value"
- ❌ "Access denied for recorder"
- ❌ "Cannot add events after close"
- ❌ "Stream already closed"

## What to Report Back

1. **Session transitions**: Did ending/starting work smoothly?
2. **Audio states**: Any stuck states or continuous listening?
3. **TTS timing**: How long from speech to response?
4. **Errors**: Any crashes or error messages?
5. **User experience**: Feel natural and responsive?

## Debug Tips

If you see issues, capture logs:
```bash
# Save full log
adb logcat -d > test_log.txt

# Filter for our components
adb logcat -d | grep -E "(Voice|Session|Error)" > filtered_log.txt
```