from fastapi import APIRouter, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
import logging
import traceback
import json
from datetime import datetime

from app.services.ai_service import ai_service
from app.services.groq_service import groq_service
from app.services.voice_service import voice_service
from app.services.transcription_service import transcription_service
from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()

@router.post("/generate", response_class=JSONResponse)
async def generate_response(request: Request):
    """
    Generate response from AI model (now using Groq's LLM service)
    """
    try:
        data = await request.json()
        user_message = data.get("message", "")
        conversation_history = data.get("history", [])
        
        if not user_message:
            return JSONResponse({"error": "No message provided"}, status_code=400)
            
        logger.info(f"Generating AI response for message: {user_message[:30]}...")
        
        # Generate AI response using Groq instead of OpenAI
        response = await groq_service.generate_response(user_message, conversation_history)
        
        if not response:
            return JSONResponse({"error": "Failed to generate response"}, status_code=500)
            
        return JSONResponse({"response": response})
        
    except Exception as e:
        logger.error(f"Error generating AI response: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)

@router.get("/status", response_class=JSONResponse)
async def check_service_status():
    """
    Diagnostic endpoint to check the status of all AI services
    """
    try:
        # Check the status of all services
        # Now using groq_service instead of ai_service for LLM
        groq_available = hasattr(groq_service, 'available') and groq_service.available
        voice_available = hasattr(voice_service, 'available') and voice_service.available
        transcription_available = hasattr(transcription_service, 'available') and transcription_service.available
        
        # Check for API keys
        openai_key_available = bool(settings.OPENAI_API_KEY)
        groq_key_available = bool(settings.GROQ_API_KEY)
        
        # Build the status response
        status = {
            "services": {
                "llm": {
                    "available": groq_available,
                    "model": getattr(groq_service, 'chat_model', "unknown") 
                },
                "tts": {
                    "available": voice_available,
                    "model": getattr(voice_service, 'tts_model', "unknown"),
                    "voice": getattr(voice_service, 'voice', "unknown")
                },
                "transcription": {
                    "available": transcription_available,
                    "model": getattr(transcription_service, 'model', "unknown")
                }
            },
            "api_keys": {
                "openai": {
                    "available": openai_key_available,
                    "key_preview": settings.OPENAI_API_KEY[:5] + "..." if openai_key_available else None
                },
                "groq": {
                    "available": groq_key_available,
                    "key_preview": settings.GROQ_API_KEY[:5] + "..." if groq_key_available else None
                }
            },
            "environment": settings.model_config.get("env_file", "unknown")
        }
        
        logger.info(f"Service status check: LLM (Groq): {groq_available}, TTS: {voice_available}, Transcription: {transcription_available}")
        
        return JSONResponse(status)
    except Exception as e:
        logger.error(f"Error checking service status: {str(e)}")
        return JSONResponse({"error": str(e), "traceback": str(traceback.format_exc())}, status_code=500)

@router.get("/test-key", response_class=JSONResponse)
async def test_openai_key():
    """
    Test the API keys to ensure they're working correctly
    """
    try:
        logger.info("Testing API keys")
        
        # Test both Groq and OpenAI
        groq_result = await groq_service.test_api()
        openai_result = await ai_service.test_api()
        
        result = {
            "groq_api": groq_result,
            "openai_api": openai_result,
            "primary_llm": "Using Groq for text completion"
        }
        
        logger.info(f"API key test results: Groq: {groq_result.get('available')}, OpenAI: {openai_result.get('available')}")
        
        return JSONResponse(result)
    except Exception as e:
        logger.error(f"Error testing API keys: {str(e)}")
        return JSONResponse({"error": str(e), "traceback": str(traceback.format_exc())}, status_code=500)

@router.websocket("/ws/chat")
async def websocket_chat(websocket: WebSocket):
    await websocket.accept()
    sequence = 1
    try:
        data = await websocket.receive_text()
        try:
            payload = json.loads(data)
        except Exception:
            await websocket.send_text(json.dumps({
                "type": "error",
                "detail": "Invalid JSON input",
                "timestamp": datetime.utcnow().isoformat() + 'Z'
            }))
            return
        message = payload.get("message", "")
        history = payload.get("history", [])
        session_id = payload.get("session_id")
        # Optionally, you can use session_id for context management
        from app.services.groq_service import groq_service
        async for chunk in groq_service.stream_chat_completion(
            message=message,
            context=history
        ):
            await websocket.send_text(json.dumps({
                "type": "chunk",
                "content": chunk,
                "sequence": sequence,
                "timestamp": datetime.utcnow().isoformat() + 'Z'
            }))
            sequence += 1
        await websocket.send_text(json.dumps({
            "type": "done",
            "sequence": sequence,
            "timestamp": datetime.utcnow().isoformat() + 'Z'
        }))
    except Exception as e:
        await websocket.send_text(json.dumps({
            "type": "error",
            "detail": str(e),
            "timestamp": datetime.utcnow().isoformat() + 'Z'
        }))
    except WebSocketDisconnect:
        logger.info("WebSocket chat disconnected") 