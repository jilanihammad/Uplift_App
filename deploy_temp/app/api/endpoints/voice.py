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

# Use unified LLM manager instead of individual services
from app.services.llm_manager import llm_manager

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
        
        # Default to opus/ogg for optimal compatibility
        format_params["response_format"] = data.get("format", "opus")  # Default format is now opus
        
        # Add voice if provided
        if voice:
            format_params["voice"] = voice
            
        if not text:
            return JSONResponse({"error": "No text provided"}, status_code=400)
            
        logger.info(f"Synthesizing voice for text: {text[:30]}... with format: {format_params}")
        
        # Create output directory if it doesn't exist
        os.makedirs("static/audio", exist_ok=True)
        
        # Generate unique filename
        timestamp = int(time.time())
        extension = ".ogg" if format_params["response_format"] in ["opus", "ogg_opus"] else ".mp3"
        output_file = f"static/audio/tts_{timestamp}{extension}"
        
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

@router.post("/tts", description="Convert text to speech")
async def text_to_speech(
    text: str = Form(...), 
    format: str = Form("opus"), 
    voice: str = Form("sage"),
    background_tasks: BackgroundTasks = None
):
    logger.info(f"Received TTS request: {text[:50]}...")
    
    try:
        # Create output directory if it doesn't exist
        os.makedirs("static/audio", exist_ok=True)
        
        # Handle file extension based on format
        extension = ".ogg" if format in ["opus", "ogg_opus"] else ".mp3"
        output_file = f"static/audio/tts_{int(time.time())}{extension}"
        
        logger.info(f"Using TTS parameters: format={format}, voice={voice}")
        
        # Use unified LLM manager for TTS
        success = await llm_manager.text_to_speech(
            text, 
            output_file, 
            response_format=format,
            voice=voice
        )
        
        if not success:
            logger.error("TTS failed via unified LLM manager")
            raise HTTPException(status_code=500, detail="Failed to convert text to speech")
        
        logger.info(f"TTS successful, audio saved to {output_file}")
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

        try:
            # Use unified LLM manager for transcription
            transcription = await llm_manager.transcribe_audio(temp.name)
            return {"text": transcription}
            
        finally:
            # Clean up temp file
            os.remove(temp.name)
            
    except Exception as e:
        logger.error(f"Error in transcribe_file: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)

@router.websocket("/ws/tts")
async def websocket_tts(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            try:
                payload = json.loads(data)
                text = payload.get("text")
                voice = payload.get("voice", "sage")
                params = payload.get("params", {})
                response_format = params.get("response_format", "opus")  # Default to opus

                if not text:
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "detail": "No text provided"
                    }))
                    continue

                try:
                    # Stream audio using unified manager
                    async for b64_chunk in llm_manager.stream_text_to_speech(
                        text,
                        voice=voice,
                        response_format=response_format
                    ):
                        await websocket.send_text(json.dumps({
                            "type": "audio_chunk",
                            "data": b64_chunk,
                            "format": response_format
                        }))
                    # When done, send a 'done' message
                    await websocket.send_text(json.dumps({
                        "type": "done",
                        "format": response_format
                    }))
                except Exception as tts_error:
                    logger.error(f"TTS WebSocket error: {str(tts_error)}")
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "detail": f"TTS error: {str(tts_error)}"
                    }))
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "detail": "Invalid JSON"
                }))
    except WebSocketDisconnect:
        logger.info("WebSocket TTS disconnected")
    except Exception as e:
        logger.error(f"WebSocket TTS error: {str(e)}")
        try:
            await websocket.send_text(json.dumps({
                "type": "error",
                "detail": str(e)
            }))
            await websocket.close()
        except:
            pass  # WebSocket might already be closed 