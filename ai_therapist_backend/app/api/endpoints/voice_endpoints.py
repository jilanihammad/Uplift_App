"""Voice processing endpoints"""
from fastapi import APIRouter, UploadFile, File, HTTPException, Request, Query
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel
from typing import Optional, Dict, Any
import logging
import base64
import io
import os
import time
import tempfile
import uuid

from app.services.llm_manager import llm_manager
from app.core.config import settings
from app.core.observability import record_latency, record_counter

logger = logging.getLogger(__name__)
router = APIRouter()


class VoiceRequest(BaseModel):
    """Request model for voice synthesis"""
    text: str
    voice: Optional[str] = None
    model: Optional[str] = None
    response_format: Optional[str] = "mp3"


class TranscriptionRequest(BaseModel):
    """Request model for transcription"""
    audio_data: str  # Base64 encoded
    audio_format: str = "mp3"
    model: Optional[str] = None


@router.post("/synthesize")
async def voice_synthesize(request: VoiceRequest):
    """Synthesize text to speech."""
    request_start = time.time()
    
    try:
        if not request.text:
            raise HTTPException(status_code=400, detail="No text provided for TTS")
        
        if not llm_manager:
            raise HTTPException(status_code=500, detail="TTS service not available")
        
        # Check for Phase 3 optimization
        phase3_enabled = os.getenv("PHASE3_TTS_OPTIMIZATION", "true").lower() == "true"
        
        if phase3_enabled:
            try:
                from app.core.phase3_fast_path import route_tts_request_fast_path, RequestPriority
                
                priority = RequestPriority.HIGH if len(request.text) < 20 else (
                    RequestPriority.LOW if len(request.text) > 200 else RequestPriority.NORMAL
                )
                
                audio_data, metadata = await route_tts_request_fast_path(
                    text=request.text,
                    voice=request.voice,
                    model=request.model,
                    priority=priority
                )
                
                total_time = (time.time() - request_start) * 1000
                ttfb = metadata.get("processing_time_ms", total_time)
                
                record_latency("tts_phase3", "total_time", total_time)
                record_latency("tts_phase3", "first_byte", ttfb)
                
                return StreamingResponse(
                    io.BytesIO(audio_data),
                    media_type="audio/mpeg",
                    headers={
                        "X-TTS-Provider": metadata.get("provider_used", "unknown"),
                        "X-Processing-Time": str(round(ttfb, 1)),
                        "X-Fast-Path-Strategy": metadata.get("fast_path_strategy", "unknown"),
                        "X-Phase": "3"
                    }
                )
            except Exception as phase3_error:
                logger.warning(f"Phase 3 TTS failed, falling back: {phase3_error}")
        
        # Legacy TTS implementation
        audio_chunks = []
        first_chunk = False
        
        async for chunk in llm_manager.stream_text_to_speech(
            text=request.text,
            voice=request.voice,
            response_format=request.response_format or "mp3"
        ):
            if not first_chunk:
                ttfb = (time.time() - request_start) * 1000
                record_latency("tts", "first_byte", ttfb)
                record_counter("tts", "requests_total")
                first_chunk = True
            audio_chunks.append(chunk)
        
        combined = base64.b64encode(base64.b64decode(''.join(audio_chunks))).decode('utf-8')
        
        return JSONResponse({
            "audio_data": combined,
            "format": request.response_format or "mp3"
        })
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"TTS error: {e}")
        raise HTTPException(status_code=500, detail=f"TTS error: {str(e)}")


@router.post("/transcribe")
async def transcribe_audio(request: TranscriptionRequest):
    """Transcribe audio from base64 data."""
    try:
        if not request.audio_data:
            raise HTTPException(status_code=400, detail="No audio data provided")
        
        if not llm_manager:
            raise HTTPException(status_code=500, detail="Transcription service not available")
        
        # Decode base64 audio
        try:
            audio_bytes = base64.b64decode(request.audio_data)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid base64 audio data")
        
        if len(audio_bytes) < 100:
            raise HTTPException(status_code=400, detail="Audio data too small")
        
        # Save to temporary file
        with tempfile.NamedTemporaryFile(delete=False, suffix=f".{request.audio_format}") as tmp:
            tmp.write(audio_bytes)
            tmp_path = tmp.name
        
        try:
            # Transcribe
            transcription = await llm_manager.transcribe_audio(tmp_path)
            
            if not transcription or not transcription.strip():
                raise HTTPException(status_code=500, detail="Transcription returned empty result")
            
            return {"text": transcription}
            
        finally:
            # Cleanup temp file
            try:
                os.remove(tmp_path)
            except Exception:
                pass
                
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Transcription error: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription error: {str(e)}")


@router.post("/transcribe_file")
async def transcribe_file(file: UploadFile = File(...)):
    """Transcribe an uploaded audio file."""
    try:
        if not llm_manager:
            raise HTTPException(status_code=500, detail="Transcription service not available")
        
        # Save uploaded file
        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as tmp:
            content = await file.read()
            tmp.write(content)
            tmp_path = tmp.name
        
        try:
            transcription = await llm_manager.transcribe_audio(tmp_path)
            return {"text": transcription}
        finally:
            try:
                os.remove(tmp_path)
            except Exception:
                pass
                
    except Exception as e:
        logger.error(f"File transcription error: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription error: {str(e)}")


# WebSocket endpoint for streaming TTS
@router.websocket("/ws/tts")
async def websocket_tts(websocket):
    """WebSocket endpoint for streaming TTS."""
    from app.api.endpoints.voice import websocket_streaming_tts
    await websocket_streaming_tts(
        websocket,
        token=Query(...),
        conversation_id=Query(default=str(uuid.uuid4())),
        voice=Query(default="sage"),
        format=Query(default="wav")
    )
