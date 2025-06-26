# TTS Intelligent Buffering Implementation

## Problem Solved
The TTS service was creating tiny rapid audio segments (11 chars, 29 chars, 26 chars) from streaming LLM responses, which overwhelmed the audio player queue and created choppy, unnatural speech.

## Solution Implemented

### 1. Text Buffering System in `TTSService`
- Added intelligent text buffering with configurable thresholds
- Buffers accumulate text until reaching meaningful chunk sizes
- Session-based buffering supports concurrent TTS streams

### 2. Smart Chunking Logic
- **Minimum threshold**: 50 characters before processing
- **Maximum buffer**: 200 characters to prevent overly long segments
- **Sentence detection**: Splits on periods, question marks, exclamation points
- **Abbreviation awareness**: Handles Dr., Mr., Mrs., etc. correctly
- **Timeout mechanism**: 2-second timeout flushes partial sentences

### 3. Key Methods Added

#### `_processTextWithBuffering()`
- Manages text buffering per session
- Decides when to process accumulated text
- Handles timeout-based flushing

#### `_shouldProcessBuffer()`
- Checks if buffer has enough content
- Detects complete sentences
- Enforces maximum buffer size

#### `_extractSentencesFromBuffer()`
- Extracts complete sentences while preserving remainder
- Finds natural break points (commas, semicolons)
- Handles edge cases gracefully

#### `streamAndPlayTTSChunked()`
- New method for processing text streams
- Manages buffering lifecycle
- Coordinates with audio playback

### 4. Integration Changes

#### Updated `AudioGenerator.processAIResponseWithStreamingTTS()`
- Now uses `streamAndPlayTTSChunked()` instead of individual chunk processing
- Maintains VAD coordination
- Preserves all callbacks and state management

#### Updated `ITTSService` interface
- Added `sessionId` parameter to `streamAndPlayTTS()`
- Added new `streamAndPlayTTSChunked()` method

## Benefits

1. **Reduced API Calls**: From 10-20 tiny chunks to 2-5 meaningful segments
2. **Natural Speech Flow**: Complete sentences instead of fragments
3. **Better Performance**: Less audio queue congestion
4. **Improved UX**: Smoother, more natural AI voice responses
5. **Resource Efficiency**: Fewer audio files to manage

## Example Transformation

**Before (3 TTS calls):**
- "I hear you" (10 chars)
- ", and it sounds really tough" (28 chars)  
- ". Can you tell me more?" (23 chars)

**After (1 TTS call):**
- "I hear you, and it sounds really tough. Can you tell me more?" (61 chars)

## Configuration

The buffering behavior can be adjusted by modifying these constants in `TTSService`:
```dart
static const int _minBufferSize = 50;     // Minimum characters
static const int _maxBufferSize = 200;    // Maximum characters
static const Duration _bufferTimeout = Duration(seconds: 2);
```

## Testing

To verify the implementation:
1. Enable debug mode and monitor logs for buffer operations
2. Test with various streaming speeds
3. Verify sentence detection with different punctuation
4. Test timeout behavior with slow streams
5. Confirm abbreviations don't break sentences prematurely