from fastapi import APIRouter, UploadFile, File, HTTPException, Depends, Request, Form, BackgroundTasks, WebSocket, WebSocketDisconnect, Query
from fastapi.responses import JSONResponse
from typing import Optional, Dict, Any
import logging
import base64
import json
import os
import aiofiles
import time
import tempfile
import asyncio
import weakref
from datetime import datetime, timezone

# Use unified LLM manager instead of individual services
from app.services.llm_manager import llm_manager

# Import our enhanced streaming pipeline
from app.services.streaming_pipeline import (
    EnhancedAsyncPipeline, 
    StreamingMessage, 
    FlowControlConfig,
    create_pipeline
)

# JWT authentication
from jose import jwt, JWTError
from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()

# Global pipeline instances for connection pooling
_pipeline_pool: Dict[str, weakref.ReferenceType] = {}
_pool_lock = asyncio.Lock()

class ConnectionManager:
    """Manage WebSocket connections with JWT authentication and connection pooling"""
    
    def __init__(self):
        self.active_connections: Dict[str, Dict[str, Any]] = {}
        self.pipeline_sessions: Dict[str, str] = {}  # session_id -> pipeline_id
        
    async def authenticate_websocket(self, websocket: WebSocket, token: str) -> Optional[Dict[str, Any]]:
        """Authenticate WebSocket connection using JWT token"""
        try:
            # Decode and verify JWT token
            payload = jwt.decode(
                token, 
                settings.SECRET_KEY, 
                algorithms=["HS256"]
            )
            
            # Extract user information
            user_id = payload.get("sub")
            if not user_id:
                logger.warning("JWT token missing user ID")
                return None
                
            # Check token expiration
            exp = payload.get("exp")
            if exp and datetime.now(timezone.utc).timestamp() > exp:
                logger.warning("JWT token expired")
                return None
                
            logger.info(f"WebSocket authentication successful for user: {user_id}")
            return {
                "user_id": user_id,
                "payload": payload
            }
            
        except JWTError as e:
            logger.warning(f"JWT authentication failed: {str(e)}")
            return None
        except Exception as e:
            logger.error(f"Authentication error: {str(e)}")
            return None
            
    async def connect(self, websocket: WebSocket, client_id: str, user_info: Dict[str, Any]):
        """Accept WebSocket connection and register client"""
        await websocket.accept()
        
        self.active_connections[client_id] = {
            "websocket": websocket,
            "user_info": user_info,
            "connected_at": datetime.now(),
            "last_activity": datetime.now()
        }
        
        logger.info(f"WebSocket client {client_id} connected for user {user_info['user_id']}")
        
    async def disconnect(self, client_id: str):
        """Remove client from active connections"""
        if client_id in self.active_connections:
            del self.active_connections[client_id]
            logger.info(f"WebSocket client {client_id} disconnected")
            
        # Clean up pipeline session if exists
        if client_id in self.pipeline_sessions:
            pipeline_id = self.pipeline_sessions[client_id]
            del self.pipeline_sessions[client_id]
            
            # Clean up pipeline if no more clients using it
            await self._cleanup_unused_pipeline(pipeline_id)
            
    async def _cleanup_unused_pipeline(self, pipeline_id: str):
        """Clean up pipeline if no clients are using it"""
        clients_using_pipeline = [
            client_id for client_id, pid in self.pipeline_sessions.items() 
            if pid == pipeline_id
        ]
        
        if not clients_using_pipeline:
            async with _pool_lock:
                if pipeline_id in _pipeline_pool:
                    pipeline_ref = _pipeline_pool[pipeline_id]
                    pipeline = pipeline_ref()
                    if pipeline:
                        try:
                            await pipeline.stop()
                            logger.info(f"Cleaned up unused pipeline: {pipeline_id}")
                        except Exception as e:
                            logger.error(f"Error cleaning up pipeline {pipeline_id}: {e}")
                    del _pipeline_pool[pipeline_id]
                    
    async def get_or_create_pipeline(self, client_id: str, config: Optional[FlowControlConfig] = None) -> EnhancedAsyncPipeline:
        """Get existing pipeline or create new one for client"""
        # Use user-based pipeline pooling to share across sessions
        user_info = self.active_connections.get(client_id, {}).get("user_info", {})
        user_id = user_info.get("user_id", "anonymous")
        pipeline_id = f"pipeline_{user_id}"
        
        async with _pool_lock:
            # Check if pipeline exists and is still valid
            if pipeline_id in _pipeline_pool:
                pipeline_ref = _pipeline_pool[pipeline_id]
                pipeline = pipeline_ref()
                if pipeline and pipeline.state.value != "error":
                    self.pipeline_sessions[client_id] = pipeline_id
                    logger.info(f"Reusing existing pipeline {pipeline_id} for client {client_id}")
                    return pipeline
                else:
                    # Clean up dead reference
                    del _pipeline_pool[pipeline_id]
                    
            # Create new pipeline
            pipeline = await create_pipeline(config)
            await pipeline.start()
            
            # Store weak reference to allow garbage collection
            _pipeline_pool[pipeline_id] = weakref.ref(pipeline)
            self.pipeline_sessions[client_id] = pipeline_id
            
            logger.info(f"Created new pipeline {pipeline_id} for client {client_id}")
            return pipeline

# Global connection manager
connection_manager = ConnectionManager()

@router.get("/ping")
async def ping_endpoint():
    """
    Cold-start prevention endpoint to keep containers warm
    Returns server status and readiness information
    """
    try:
        # Test LLM manager availability
        llm_available = hasattr(llm_manager, 'get_completion') and callable(getattr(llm_manager, 'get_completion'))
        
        # Check pipeline creation capability
        try:
            test_config = FlowControlConfig()
            pipeline_ready = True
        except Exception:
            pipeline_ready = False
            
        status = {
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "services": {
                "llm_manager": llm_available,
                "streaming_pipeline": pipeline_ready,
                "websocket_ready": True
            },
            "cold_start_prevention": True
        }
        
        logger.info("Ping endpoint accessed - cold start prevented")
        return JSONResponse(content=status)
        
    except Exception as e:
        logger.error(f"Ping endpoint error: {str(e)}")
        return JSONResponse(
            content={
                "status": "degraded", 
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }, 
            status_code=503
        )

@router.websocket("/ws/tts/speech")
async def websocket_streaming_tts(
    websocket: WebSocket,
    token: str = Query(..., description="JWT authentication token"),
    conversation_id: str = Query(..., description="Unique conversation identifier"),
    voice: str = Query(default="sage", description="TTS voice to use"),
    format: str = Query(default="wav", description="Audio format (wav for lowest latency)")
):
    """
    Enhanced WebSocket endpoint for real-time streaming TTS speech generation
    Integrates with the enhanced pipeline for sub-400ms latency
    
    Features:
    - JWT authentication
    - Connection pooling and reuse
    - Flow control and backpressure
    - Jitter buffer support
    - Sequence preservation
    - Performance monitoring
    """
    client_id = f"client_{int(time.time() * 1000)}_{id(websocket)}"
    
    try:
        # Authenticate WebSocket connection
        user_info = await connection_manager.authenticate_websocket(websocket, token)
        if not user_info:
            await websocket.close(code=1008, reason="Authentication failed")
            return
            
        # Connect client
        await connection_manager.connect(websocket, client_id, user_info)
        
        # Get or create pipeline for this client
        config = FlowControlConfig()
        pipeline = await connection_manager.get_or_create_pipeline(client_id, config)
        
        # Register client with pipeline
        init_frame = await pipeline.register_client(client_id, websocket)
        
        # Send initialization frame with jitter buffer guidance
        await websocket.send_text(json.dumps(init_frame))
        
        logger.info(f"Streaming WebSocket client {client_id} ready for conversation {conversation_id}")
        
        # Main message processing loop
        while True:
            try:
                # Receive message from client
                data = await websocket.receive_text()
                message_data = json.loads(data)
                
                message_type = message_data.get("type", "text")
                
                if message_type == "text":
                    # Process text message through pipeline
                    text_content = message_data.get("message", "")
                    priority = message_data.get("priority", 1)
                    
                    if not text_content.strip():
                        await websocket.send_text(json.dumps({
                            "type": "error",
                            "error": "Empty message content"
                        }))
                        continue
                        
                    # Create streaming message
                    streaming_message = StreamingMessage(
                        message_id=f"msg_{int(time.time() * 1000)}",
                        conversation_id=conversation_id,
                        user_message=text_content,
                        priority=priority,
                        metadata={
                            "client_id": client_id,
                            "voice": voice,
                            "format": format,
                            "user_id": user_info["user_id"]
                        }
                    )
                    
                    # Add message to pipeline
                    success = await pipeline.add_message(streaming_message)
                    
                    if not success:
                        await websocket.send_text(json.dumps({
                            "type": "error", 
                            "error": "Pipeline queue full - please try again"
                        }))
                        continue
                        
                    # Send acknowledgment
                    await websocket.send_text(json.dumps({
                        "type": "message_received",
                        "message_id": streaming_message.message_id,
                        "timestamp": streaming_message.timestamp.isoformat()
                    }))
                    
                elif message_type == "ping":
                    # Handle ping/pong for connection keepalive
                    await websocket.send_text(json.dumps({
                        "type": "pong",
                        "timestamp": datetime.now().isoformat()
                    }))
                    
                elif message_type == "interrupt":
                    # Handle client interruption (future enhancement)
                    logger.info(f"Client {client_id} requested interruption")
                    await websocket.send_text(json.dumps({
                        "type": "interrupted",
                        "timestamp": datetime.now().isoformat()
                    }))
                    
                else:
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "error": f"Unknown message type: {message_type}"
                    }))
                    
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "error": "Invalid JSON format"
                }))
                continue
            except Exception as e:
                logger.error(f"Error processing WebSocket message for {client_id}: {str(e)}")
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "error": f"Processing error: {str(e)}"
                }))
                continue
                
    except WebSocketDisconnect:
        logger.info(f"WebSocket client {client_id} disconnected normally")
    except Exception as e:
        logger.error(f"WebSocket error for client {client_id}: {str(e)}")
        try:
            await websocket.close(code=1011, reason="Internal server error")
        except:
            pass  # WebSocket might already be closed
    finally:
        # Clean up client connection and pipeline session
        await connection_manager.disconnect(client_id)
        
        # Unregister from pipeline if it exists
        if client_id in connection_manager.pipeline_sessions:
            pipeline_id = connection_manager.pipeline_sessions[client_id]
            if pipeline_id in _pipeline_pool:
                pipeline_ref = _pipeline_pool[pipeline_id]
                pipeline = pipeline_ref()
                if pipeline:
                    try:
                        await pipeline.unregister_client(client_id)
                    except Exception as e:
                        logger.error(f"Error unregistering client {client_id}: {e}")

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