from fastapi import APIRouter, UploadFile, File, HTTPException, Depends, Request, Form, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from typing import Optional
import logging
import base64
import json
import os
import aiofiles
import time
import tempfile

from app.services.voice_service import voice_service
from app.services.transcription_service import transcription_service
from app.services.openai_service import openai_service

logger = logging.getLogger(__name__)

router = APIRouter()

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

@router.post("/transcribe", response_class=JSONResponse)
async def transcribe_audio(file: UploadFile = File(...)):
    """
    Transcribe audio file to text
    """
    try:
        if not file:
            return JSONResponse({"error": "No file provided"}, status_code=400)
            
        logger.info(f"Transcribing audio file: {file.filename}")
        
        # Use our new transcription service
        text = await transcription_service.transcribe_audio(file)
        
        if not text:
            return JSONResponse({"error": "Failed to transcribe audio"}, status_code=500)
            
        return JSONResponse({"text": text})
        
    except Exception as e:
        logger.error(f"Error transcribing audio: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)

@router.post("/tts", description="Convert text to speech")
async def text_to_speech(text: str = Form(...), format: str = Form(None), bitrate: str = Form(None), mono: bool = Form(True), background_tasks: BackgroundTasks = None):
    logger.info(f"Received TTS request: {text[:50]}...")
    
    try:
        # Create output directory if it doesn't exist
        os.makedirs("static/audio", exist_ok=True)
        
        # Get format parameters
        format_params = {}
        if format:
            format_params["response_format"] = format
        else:
            format_params["response_format"] = "ogg_opus"  # Default to optimized format
            
        if bitrate:
            format_params["bitrate"] = bitrate
        else:
            format_params["bitrate"] = "24k"  # Default to optimized bitrate
            
        format_params["mono"] = mono  # Default to mono audio

        # Handle file extension based on format
        extension = ".ogg" if format_params["response_format"] in ["opus", "ogg_opus"] else ".mp3"
        output_file = f"static/audio/tts_{int(time.time())}{extension}"
        
        logger.info(f"Using TTS parameters: {format_params}")
        
        # Try using OpenAI TTS service first
        logger.info("Attempting TTS with OpenAI service")
        openai_success = await openai_service.text_to_speech(text, output_file, format_params)
        
        if openai_success:
            logger.info(f"OpenAI TTS successful, audio saved to {output_file}")
            return {
                "status": "success",
                "message": "Text converted to speech successfully",
                "audio_url": f"/static/audio/{os.path.basename(output_file)}"
            }
        
        # Fall back to the voice service if OpenAI fails
        logger.info("OpenAI TTS failed, falling back to voice service")
        voice_result = await voice_service.text_to_speech(text, output_file)
        
        if not voice_result["success"]:
            logger.error(f"Voice service TTS failed: {voice_result['message']}")
            raise HTTPException(status_code=500, detail=voice_result["message"])
        
        logger.info(f"Voice service TTS successful, audio saved to {output_file}")
        return {
            "status": "success",
            "message": "Text converted to speech successfully",
            "audio_url": f"/static/audio/{os.path.basename(output_file)}"
        }
        
    except Exception as e:
        logger.error(f"Error in TTS endpoint: {str(e)}")
        logger.exception("TTS error details:")
        raise HTTPException(status_code=500, detail=f"Failed to convert text to speech: {str(e)}")

@router.post("/voice/transcribe_file")
async def transcribe_file(file: UploadFile = File(...)):
    try:
        # Save the uploaded file to a temp location
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp3")
        temp.write(await file.read())
        temp.close()

        # Call your transcription service (update as needed)
        transcription = await openai_service.transcribe_audio(temp.name)

        # Clean up temp file
        os.remove(temp.name)

        return {"text": transcription}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

@router.websocket("/ws/tts")
async def websocket_tts(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            # TODO: Implement TTS streaming logic here
            # For now, echo the received message
            await websocket.send_text(f"Echo: {data}")
    except WebSocketDisconnect:
        logger.info("WebSocket TTS disconnected") 