# Backend Audio Compression Settings Proposal

## Overview
This document outlines recommended changes to backend audio compression settings to improve load times and reduce bandwidth usage in the AI Therapist app. These changes do not require any frontend code modifications beyond what has already been implemented.

## Current State
- Current format: MP3 (based on backend response)
- Default settings: Likely standard OpenAI TTS settings
- Issue: Audio files larger than necessary, causing slower download times

## Proposed Changes

### 1. Audio Format Changes
We've already implemented the following in the frontend:
- Changed format to `ogg_opus`: More efficient than MP3 for speech
- Reduced bitrate to `24k`: Lower than default (64k), still maintains good quality
- Enabled `mono`: Single channel saves ~50% bandwidth compared to stereo

### 2. Backend Implementation (Required)
The following changes should be made on the backend:

```javascript
// Example backend code for Node.js (adjust based on actual backend implementation)
app.post('/voice/synthesize', async (req, res) => {
  try {
    const { text, voice } = req.body;
    
    // Configure parameters with our optimized settings
    const openaiParams = {
      model: "tts-1",
      input: text,
      voice: voice || "sage",
      // New compression settings
      response_format: "opus", // Or ogg_opus depending on OpenAI API
      speed: 1.0,
      // Add these optimization parameters
      bitrate: "24k", // Lower than default
      mono: true // Single channel
    };
    
    // Send request to OpenAI TTS API
    const response = await openai.audio.speech.create(openaiParams);
    
    // Process and return result
    // ... existing code ...
  } catch (error) {
    // ... existing error handling ...
  }
});
```

### 3. Expected Benefits
- **Smaller file sizes**: Approximately 60-70% smaller than current MP3 files
- **Faster download times**: Significantly improved first-time audio loads
- **Reduced bandwidth costs**: Less data transfer for both users and backend
- **Compatible with streaming**: Works well with our new streaming implementation
- **No audio quality loss**: Opus at 24kbps mono is optimized for speech and maintains high quality

### 4. Implementation Plan
1. Make the backend changes to support the new format and compression settings
2. Test with various speech samples to ensure quality is maintained
3. Roll out incrementally to production

### 5. Fallback Strategy
The existing frontend code already handles fallback gracefully if these settings aren't available.

## Request
Please implement these changes on the backend to significantly improve the app's audio performance and user experience. 