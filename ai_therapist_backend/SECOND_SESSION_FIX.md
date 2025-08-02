# Second Session Audio/TTS Fix

## Problem
Audio/TTS works in the first therapy session but fails in subsequent sessions. The issue was caused by the backend streaming pipeline being reused across sessions without proper state cleanup.

## Root Cause
1. Pipeline pooling used only user_id for identification, causing the same pipeline instance to be reused across different sessions
2. Pipeline state was not properly reset between sessions
3. WebSocket disconnect handler didn't force pipeline cleanup

## Solution Implemented

### 1. Pipeline ID Generation (voice.py)
- Modified `get_or_create_pipeline()` to include conversation_id in pipeline identification
- This ensures each session gets its own unique pipeline instance
```python
pipeline_id = f"pipeline_{user_id}_{conversation_id}"
```

### 2. WebSocket Disconnect Cleanup (voice.py)
- Enhanced the disconnect handler to force pipeline cleanup
- Pipeline is stopped and removed from pool on disconnect
- This ensures the next session gets a fresh pipeline

### 3. Pipeline State Reset (streaming_pipeline.py)
- Enhanced `stop()` method to perform full state reset:
  - Clear all client tracking
  - Reset timing and metrics
  - Reset interrupt state
  - Reset chunk counters
  - Clear all queues
- Added `reset()` method for cases where pipeline reuse is desired

### 4. Minimal Logging
- Added performance-optimized logging at key lifecycle points:
  - Pipeline creation
  - Pipeline cleanup on disconnect
  - Pipeline stop completion
- Logging is minimal and non-blocking to avoid TTS delays

## Testing
To verify the fix works:
1. Start a therapy session and verify audio/TTS works
2. End the session
3. Start a new session immediately
4. Verify audio/TTS works in the second session

## Monitoring
Look for these log messages to track pipeline lifecycle:
- "Created new pipeline pipeline_{user_id}_{conversation_id}"
- "Cleaning up pipeline pipeline_{user_id}_{conversation_id}"
- "Pipeline stopped with full state reset"