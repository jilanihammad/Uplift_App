# Backend Optimization Implementation Plan

## Files to Modify

1. **ai_therapist_backend/app/services/openai_service.py** - Main file handling TTS API calls
2. **ai_therapist_backend/app/api/endpoints/voice.py** - Voice endpoint that accepts format parameters

## Changes Required

### 1. Update `openai_service.py` - text_to_speech method

```python
@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
async def text_to_speech(self, text: str, output_path: str, format_params: dict = None) -> bool:
    """
    Convert text to speech using OpenAI's TTS API
    
    Args:
        text: Text to convert to speech
        output_path: Path to save the audio file
        format_params: Optional parameters for audio format and quality
        
    Returns:
        Boolean indicating success or failure
    """
    if not self.available:
        logger.warning("OpenAI TTS service unavailable - API key not set")
        raise Exception("TTS service unavailable - API key not set")
        
    if not text:
        logger.error("Empty text provided for TTS")
        raise ValueError("Empty text provided for TTS")
        
    try:
        logger.info(f"Converting text to speech using model: {self.tts_model}, voice: {self.tts_voice}")
        
        # Handle file extension based on format
        audio_format = format_params.get("response_format", "mp3") if format_params else "mp3"
        if audio_format == "opus" or audio_format == "ogg_opus":
            # Make sure output path has correct extension
            if not output_path.endswith((".opus", ".ogg")):
                output_path = output_path.rsplit(".", 1)[0] + ".ogg"
        
        # Prepare API call
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        # Start with base payload
        payload = {
            "model": self.tts_model,
            "input": text,
            "voice": self.tts_voice,
            "response_format": "mp3"  # Default
        }
        
        # Update with any format parameters
        if format_params:
            payload.update(format_params)
            
        logger.info(f"Using TTS parameters: format={payload.get('response_format')}, voice={payload.get('voice')}")
        
        # Make API call
        logger.info(f"Making OpenAI API call to {self.tts_endpoint}")
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                self.tts_endpoint,
                headers=headers,
                json=payload,
                timeout=60.0
            )
            
            if response.status_code != 200:
                logger.error(f"Error from OpenAI TTS API: {response.status_code} - {response.text}")
                raise Exception(f"TTS API error: {response.status_code} - {response.text}")
            
            # Save the audio file
            try:
                # Ensure directory exists
                os.makedirs(os.path.dirname(output_path), exist_ok=True)
                
                # Write the audio file
                with open(output_path, 'wb') as f:
                    f.write(response.content)
                    
                logger.info(f"TTS audio saved to {output_path}")
                return True
                
            except Exception as e:
                logger.error(f"Error saving TTS audio file: {str(e)}")
                logger.error(traceback.format_exc())
                raise Exception(f"Error saving TTS audio file: {str(e)}")
                
    except Exception as e:
        logger.error(f"Error in OpenAI TTS: {str(e)}")
        logger.error(traceback.format_exc())
        raise Exception(f"TTS error: {str(e)}")
```

### 2. Update `voice.py` - synthesize_voice endpoint

```python
@router.post("/synthesize", response_class=JSONResponse)
async def synthesize_voice(request: Request):
    """
    Generate voice from text using TTS service
    """
    try:
        data = await request.json()
        text = data.get("text", "")
        voice = data.get("voice", None)
        
        # Extract format parameters (new)
        format_params = {}
        
        # Get format parameters with defaults for optimal performance
        format_params["response_format"] = data.get("format", "ogg_opus")  # Default to optimized format
        
        # Add bitrate parameter if specified
        if "bitrate" in data:
            format_params["bitrate"] = data.get("bitrate")
        else:
            format_params["bitrate"] = "24k"  # Default to optimized bitrate
            
        # Add mono parameter if specified
        if "mono" in data:
            format_params["mono"] = data.get("mono", True)
        else:
            format_params["mono"] = True  # Default to mono for better performance
        
        # Set voice if provided
        if voice:
            voice_service.set_voice(voice)
            
        if not text:
            return JSONResponse({"error": "No text provided"}, status_code=400)
            
        logger.info(f"Synthesizing voice for text: {text[:30]}... with format: {format_params}")
        
        # Generate audio with format parameters
        audio_url = await voice_service.generate_speech(text, format_params)
        
        if not audio_url:
            return JSONResponse({"error": "Failed to generate speech"}, status_code=500)
            
        return JSONResponse({"url": audio_url})
        
    except Exception as e:
        logger.error(f"Error synthesizing voice: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)
```

### 3. Update `voice_service.py` - generate_speech method

```python
async def generate_speech(self, text: str, format_params: dict = None) -> Optional[str]:
    """Generate speech from text and return the URL to the generated audio file"""
    if not text:
        raise ValueError("No text provided for speech generation")
        
    if not self.available:
        raise ValueError("Voice service unavailable - API key not set")
        
    # Use OpenAI API to generate speech
    try:
        # Get format extension
        format_type = format_params.get("response_format", "mp3") if format_params else "mp3"
        extension = ".ogg" if format_type in ["opus", "ogg_opus"] else ".mp3"
        
        # Generate a unique filename for the audio file
        filename = f"{uuid.uuid4()}{extension}"
        file_path = os.path.join(self.audio_dir, filename)
        
        # Ensure the directory exists
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        
        # Call the OpenAI TTS API
        from app.services.openai_service import openai_service
        tts_success = await openai_service.text_to_speech(text, file_path, format_params)
        
        logger.info(f"TTS result: {'Success' if tts_success else 'Failed'}")
        
        # Return the URL to the audio file
        return f"/audio/{filename}"
        
    except Exception as e:
        logger.error(f"Error generating speech: {str(e)}")
        logger.error(traceback.format_exc())
        raise Exception(f"Speech generation failed: {str(e)}")
```

## Testing Process

1. Update the backend code with these changes
2. Deploy to a test environment
3. Make test API calls to the `/voice/synthesize` endpoint with different format parameters:

### Test Request 1: Default optimized settings
```json
{
  "text": "This is a test of the optimized audio format",
  "voice": "sage"
}
```

### Test Request 2: Custom bitrate
```json
{
  "text": "This is a test of the optimized audio format with custom bitrate",
  "voice": "sage",
  "bitrate": "32k"
}
```

### Test Request 3: Fallback MP3 format
```json
{
  "text": "This is a test of MP3 format",
  "voice": "sage",
  "format": "mp3"
}
```

4. Verify the audio quality and file size for each test
5. Compare download speeds and playback performance in the app

## Expected Improvements

- Audio file sizes reduced by 60-70%
- Faster audio downloads and streaming starts
- Improved playback performance on lower-bandwidth connections
- Reduced backend bandwidth costs

## Important Notes

- OpenAI may change their API parameters or available formats over time
- These changes ensure the app frontend can still work with the backend regardless of format
- Error handling is improved to give better feedback when format issues occur 