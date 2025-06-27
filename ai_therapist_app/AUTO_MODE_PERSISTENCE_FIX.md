# Auto Mode Persistence Fix

## Problem Summary
The auto mode was getting disabled during TTS conversations and not being properly restored, causing Maya to stop listening automatically after speaking.

## Root Cause Analysis
1. **`pauseVAD()` method**: Was blindly setting `_autoModeEnabled = false` without saving the previous state
2. **`resumeVAD()` method**: Was blindly setting `_autoModeEnabled = true` without considering the actual previous state  
3. **TTS completion flow**: The TTS state callback mechanism wasn't properly restoring auto mode state
4. **Missing debug logging**: Hard to track when and why auto mode was being disabled

## Fixes Implemented

### 1. State Preservation in pauseVAD() 
- Added `_autoModeEnabledBeforePause` to save auto mode state before TTS
- Added `_isPausedForTTS` flag to track if currently paused for TTS
- Added guard against duplicate pause operations
- Now preserves the original auto mode state instead of blindly disabling

### 2. State Restoration in resumeVAD()
- Modified to restore the saved auto mode state instead of blindly enabling
- Added guards to prevent inappropriate VAD resume calls
- Only starts VAD if auto mode was actually enabled before pause

### 3. Enhanced TTS Completion Flow
- Modified `_enterAiSpeakingComplete()` to check for and restore paused TTS state
- Added auto mode restoration logic in the TTS completion callback
- Enhanced error handling to prevent auto mode from getting stuck disabled

### 4. Comprehensive Debug Logging
- Added `[AUTO-MODE-DEBUG]` prefix for all auto mode state changes
- Log statements now include the reason for each state change
- Added logging to track pause/resume state transitions
- Enhanced TTS state change logging with pause state information

### 5. Backup Resume Mechanism
- Modified AudioGenerator to call both TTS state callback AND VAD resume callback
- Ensures auto mode is restored even if primary TTS completion flow fails
- Added error handling for resume callback failures

### 6. Resource Cleanup
- Added cleanup of new state variables in dispose() method
- Reset pause state variables to prevent memory leaks
- Ensures clean state for next session

## Key Changes Made

### AutoListeningCoordinator.dart:
- Added `_autoModeEnabledBeforePause` and `_isPausedForTTS` state variables
- Enhanced `pauseVAD()` with state preservation and duplicate operation guards
- Enhanced `resumeVAD()` with proper state restoration logic
- Enhanced `_enterAiSpeakingComplete()` with auto mode restoration
- Added comprehensive debug logging throughout
- Enhanced `dispose()` method to clean up new state variables

### AudioGenerator.dart:
- Added backup VAD resume callback call after TTS completion
- Enhanced error handling for resume callback failures
- Ensures auto mode restoration through multiple pathways

## Expected Behavior After Fix

1. **During TTS Start**: Auto mode state is saved, then temporarily disabled
2. **During TTS Playback**: Auto mode remains disabled to prevent echo loops
3. **After TTS Completion**: Original auto mode state is restored automatically
4. **If Auto Mode was Enabled**: VAD listening resumes automatically
5. **If Auto Mode was Disabled**: VAD remains disabled (user preference preserved)

## Debug Information
All auto mode state changes now include detailed logging with:
- Current auto mode state
- Saved auto mode state
- Pause/resume state flags
- Reason for each state change
- TTS completion flow tracking

Look for `[AUTO-MODE-DEBUG]` in logs to track auto mode persistence issues.

## Testing Recommendations
1. Start conversation with auto mode ON
2. Have Maya speak (TTS should pause auto mode)
3. After Maya finishes speaking, verify auto mode is restored to ON
4. Start conversation with auto mode OFF  
5. Have Maya speak (should remain OFF after speaking)
6. Test conversation flow continuity with multiple TTS cycles

The fix ensures auto mode persistence throughout the entire conversation flow while maintaining user preferences.