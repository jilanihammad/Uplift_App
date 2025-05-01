# Audio Optimization for AI Therapist Backend

This document explains the audio optimization changes implemented in the AI Therapist backend to improve TTS (Text-to-Speech) performance and reduce bandwidth usage.

## Overview

The original implementation used MP3 format with default settings, resulting in larger audio files and slower download times. The new implementation:

1. Uses Opus audio format (via ogg_opus parameter to OpenAI API)
2. Reduces bitrate to 24k (sufficient for speech)
3. Uses mono audio rather than stereo
4. Adds proper file extension handling (.ogg for Opus format)

## Changes Made

### 1. OpenAI Service (`app/services/openai_service.py`)

Updated the `text_to_speech` method to:
- Accept format parameters
- Handle different audio formats and file extensions
- Pass format parameters to the OpenAI API
- Log the parameters used

```python
@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
async def text_to_speech(self, text: str, output_path: str, format_params: dict = None) -> bool:
    # Method implementation
    # ...
    
    # Handle file extension based on format
    audio_format = format_params.get("response_format", "mp3") if format_params else "mp3"
    if audio_format == "opus" or audio_format == "ogg_opus":
        # Make sure output path has correct extension
        if not output_path.endswith((".opus", ".ogg")):
            output_path = output_path.rsplit(".", 1)[0] + ".ogg"
    
    # ...
    
    # Update with any format parameters
    if format_params:
        payload.update(format_params)
    
    # ...
```

### 2. Voice API (`app/api/endpoints/voice.py`)

Updated the `/synthesize` endpoint to:
- Accept format parameters from API requests
- Set optimized defaults (ogg_opus format, 24k bitrate, mono audio)
- Pass parameters to the voice service

```python
@router.post("/synthesize", response_class=JSONResponse)
async def synthesize_voice(request: Request):
    # ...
    
    # Extract format parameters
    format_params = {}
    format_params["response_format"] = data.get("format", "ogg_opus")  # Default to optimized format
    if "bitrate" in data:
        format_params["bitrate"] = data.get("bitrate")
    else:
        format_params["bitrate"] = "24k"  # Default to optimized bitrate
    # ...
    
    audio_url = await voice_service.generate_speech(text, format_params)
    # ...
```

Also updated the `/tts` endpoint with similar changes.

### 3. Voice Service (`app/services/voice_service.py`)

Updated the `generate_speech` method to:
- Accept format parameters
- Use proper file extensions based on the format
- Pass parameters to the OpenAI service

```python
async def generate_speech(self, text: str, format_params: dict = None) -> Optional[str]:
    # ...
    
    # Get format extension
    format_type = format_params.get("response_format", "mp3") if format_params else "mp3"
    extension = ".ogg" if format_type in ["opus", "ogg_opus"] else ".mp3"
    
    # Generate a unique filename with the correct extension
    filename = f"{uuid.uuid4()}{extension}"
    # ...
    
    # Pass format parameters to the text_to_speech method
    tts_success = await openai_service.text_to_speech(text, file_path, format_params)
    # ...
```

## Expected Benefits

1. **File Size Reduction**: Approximately 60-70% smaller files compared to MP3
2. **Faster Downloads**: Smaller files mean quicker API responses
3. **Better Mobile Experience**: Reduced data usage is especially beneficial on mobile
4. **Lower Bandwidth Costs**: Reduces Google Cloud egress bandwidth costs

## Testing

A test script is provided in `tests/test_audio_compression.py` to verify the changes:

```bash
cd ai_therapist_backend
python tests/test_audio_compression.py --url=https://your-backend-url.run.app
```

The script tests various audio formats and settings and compares:
- File sizes
- Download times
- Total response times

## API Usage

Clients can now specify audio format parameters when making requests:

```json
{
  "text": "This is sample text to convert to speech",
  "voice": "sage",
  "format": "ogg_opus",
  "bitrate": "24k",
  "mono": true
}
```

Parameters:
- `format`: Audio format to use (default: "ogg_opus", can be "mp3" for backward compatibility)
- `bitrate`: Audio bitrate (default: "24k", can be "16k" for even smaller files or "32k" for higher quality)
- `mono`: Whether to use mono audio (default: true)

## Deployment

To deploy these changes to Google Cloud Run:

1. Run the deployment script:
   ```bash
   cd ai_therapist_backend
   ./scripts/deploy_audio_optimizations.ps1
   ```

2. Test the deployed changes using the test script.

## Further Optimization Ideas

1. **Server-side Caching**: Cache frequently used phrases to avoid regenerating audio
2. **Chunked Audio Streaming**: For longer responses, stream chunks as they're generated
3. **Content Delivery Network (CDN)**: Use a CDN for audio file delivery
4. **Progressive Compression**: Generate high-quality audio initially, then compress more for storage

## Troubleshooting

If you encounter issues:

1. Check the backend logs for any error messages
2. Verify that the OpenAI API accepts the format parameters you're trying to use
3. Make sure file extensions match the format (.ogg for Opus, .mp3 for MP3)
4. Test with the default MP3 format to rule out API or connectivity issues

## Implementation Details

The implementation defaults to Opus audio format with a 24k bitrate in mono, which provides an excellent balance between audio quality and file size for speech content. These settings were chosen specifically for mobile applications where bandwidth and data usage are important considerations. 