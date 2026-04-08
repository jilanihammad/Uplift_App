"""
Voice synthesis and transcription REST endpoints.

Contains:
- /synthesize - TTS synthesis endpoint
- /transcribe - Audio transcription endpoint
"""
import logging
import os
import tempfile
import time

from fastapi import APIRouter, UploadFile, File, Request
from fastapi.responses import JSONResponse

from app.services.llm_manager import llm_manager
from app.utils.audio_path import ensure_wav, ensure_basename_no_extension

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("/synthesize", response_class=JSONResponse)
async def synthesize_voice(request: Request):
    """
    Generate voice from text using TTS service via unified LLM manager
    """
    try:
        data = await request.json()
        text = data.get("text", "")
        voice = data.get("voice", None)

        # Extract format parameters
        format_params = {}

        # Default to wav for optimal compatibility
        format_params["response_format"] = data.get("format", "wav")  # Default format is now wav

        # Add voice if provided
        if voice:
            format_params["voice"] = voice

        if not text:
            return JSONResponse({"error": "No text provided"}, status_code=400)

        logger.info(f"Synthesizing voice for text: {text[:30]}... with format: {format_params}")

        # Create output directory if it doesn't exist
        os.makedirs("static/audio", exist_ok=True)

        # Generate unique filename WITHOUT extension - let ensure_wav handle extensions
        timestamp = int(time.time())
        filename_base = f"tts_{timestamp}"
        ensure_basename_no_extension(filename_base)  # Safety check
        output_file = ensure_wav(f"static/audio/{filename_base}")

        # Generate audio using unified manager
        success = await llm_manager.text_to_speech(text, output_file, **format_params)

        if not success:
            return JSONResponse({"error": "Failed to generate speech"}, status_code=500)

        # Return URL to the generated audio file
        audio_url = f"/static/audio/{os.path.basename(output_file)}"
        return JSONResponse({"url": audio_url})

    except Exception as e:
        logger.error(f"Error synthesizing voice: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)


@router.post("/transcribe", response_class=JSONResponse)
async def transcribe_audio(file: UploadFile = File(...)):
    """
    Transcribe audio file to text using unified LLM manager
    """
    try:
        if not file:
            return JSONResponse({"error": "No file provided"}, status_code=400)

        logger.info(f"Transcribing audio file: {file.filename}")

        # Save uploaded file to temporary location
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=f".{file.filename.split('.')[-1]}")
        temp.write(await file.read())
        temp.close()

        try:
            # Use unified LLM manager for transcription
            text = await llm_manager.transcribe_audio(temp.name)

            if not text:
                return JSONResponse({"error": "Failed to transcribe audio"}, status_code=500)

            return JSONResponse({"text": text})

        finally:
            # Clean up temp file
            os.remove(temp.name)

    except Exception as e:
        logger.error(f"Error transcribing audio: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)
